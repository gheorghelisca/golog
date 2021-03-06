module World
  (Direction(..), ColorString, TrafficLightState(..), StreetLUT, Street, World,
   color, maxX, maxY, streetLut, carLut, switchLights, mkStreet, mkWorld,
   direction, successor, reachable) where

import Data.List (minimumBy)
import Data.Maybe (catMaybes, isNothing)
import qualified Data.Map as Map

data Direction = North | East | South | West |
                 NorthEast | NorthWest | SouthEast | SouthWest
   deriving (Eq, Show)

type CarSymbol = Char
type StreetName = String
type ColorString = String

data Street a = Street { _name     :: StreetName
                       , color     :: ColorString
                       , wayPoints :: [(a, a)]
                       , points    :: [((a, a), Direction)]
                       }
   deriving Show

data TrafficLightState = Green | Yellow
   deriving (Eq, Show)

data TrafficLight a = TrafficLight { lightX          :: a
                                   , lightY          :: a
                                   , crossingStreets :: [Street a]
                                   , state           :: (TrafficLightState, Int)
                                   }
   deriving Show

type StreetLUT a = Map.Map (a, a) (Direction, Maybe TrafficLightState, Street a)
type CarLUT a = Map.Map (a, a) CarSymbol

data World a = World { maxX      :: a
                     , maxY      :: a
                     , streets   :: [Street a]
                     , lights    :: [TrafficLight a]
                     , streetLut :: StreetLUT a
                     , carLut    :: CarLUT a
                     }
   deriving Show

neighbors :: (Eq a, Num a) => (a, a) -> [(a, a)]
neighbors (x,y) = [(x',y') | x' <- [x-1,x,x+1], y' <- [y-1,y,y+1], (x,y) /= (x',y')]

-- | Returns the cardinal direction in which @p1@ lies from the point of view of
-- @p0@.
direction :: Ord a => (a, a) -> (a, a) -> Direction
direction (x0,y0) (x1,y1) | x0 <  x1 && y0 == y1 = East
                          | x0 >  x1 && y0 == y1 = West
                          | x0 == x1 && y0 <  y1 = South
                          | x0 == x1 && y0 >  y1 = North
                          | x0 <  x1 && y0 <  y1 = SouthEast
                          | x0 >  x1 && y0 <  y1 = SouthWest
                          | x0 <  x1 && y0 >  y1 = NorthEast
                          | x0 >  x1 && y0 >  y1 = NorthWest
                          | otherwise            = error "direction: same points"

successor :: (Ord a, Num a) => (a, a) -> Direction -> (a, a)
successor (x,y) West      = (x-1,y)
successor (x,y) North     = (x,y-1)
successor (x,y) East      = (x+1,y)
successor (x,y) South     = (x,y+1)
successor (x,y) NorthWest = (x-1,y-1)
successor (x,y) NorthEast = (x+1,y-1)
successor (x,y) SouthWest = (x-1,y+1)
successor (x,y) SouthEast = (x+1,y+1)

-- | Points legally reachable from the current coordinate.
-- This depends on the road segments and the current traffic lights.
reachable :: (Ord a, Num a) => World a -> (a, a) -> [(a, a)]
reachable w p0 = filter dirOk (neighbors p0)
   where dirOk p1 = maybe False (\(d,ls,_) -> ls /= Just Yellow && direction p0 p1 == d) (Map.lookup p1 (streetLut w))

bounds :: Ord a => World a -> ((a, a), (a, a))
bounds w = (minimum $ map (minimum . map fst . points) (streets w),
            maximum $ map (maximum . map fst . points) (streets w))

mkStreet :: StreetName -> ColorString -> [(a, a)] -> Street a
mkStreet n c ps = Street n c ps undefined

mkWorld :: Int -> Int -> [Street Int] -> World Int
mkWorld width height ss' = world{lights = mkLights world}{streetLut = mkLut world}
   where world = World { maxX      = width
                       , maxY      = height
                       , streets   = map mkPoints ss'
                       , lights    = undefined
                       , streetLut = undefined
                       , carLut    = Map.empty
                       }
         mkPoints :: (Ord a, Num a) => Street a -> Street a
         mkPoints s = s{points = mkPoints' (wayPoints s)}
            where mkPoints' []                     = []
                  mkPoints' [_]                    = []
                  mkPoints' (p0:p2:ps) | p0 == p2  = mkPoints' (p2:ps)
                                       | otherwise = (p1,d) : mkPoints' (p1:p2:ps)
                     where p1 = minimumBy (\q1 q2 -> compare (manhattan q1 p2) (manhattan q2 p2)) (neighbors p0)
                           d  = direction p0 p1
         mkLights :: (Enum a, Eq a, Num a) => World a -> [TrafficLight a]
         mkLights w = catMaybes (map mkL ps)
            where ps = [(x,y) | x <- [0..maxX w], y <- [0..maxY w]]
                  mkL (x,y) = case crossing (x,y) of []  -> Nothing
                                                     [_] -> Nothing
                                                     ss  -> Just $ TrafficLight x y ss (Green, 0)
                  crossing (x,y) = filter (not . isNothing . lookup (x,y) . points) (streets w)
         mkLut :: Ord a => World a -> StreetLUT a
         mkLut w = foldr addStreet Map.empty (streets w)
            where addStreet s m0 = foldr (\(p,d) m -> Map.insert p (d,Nothing,s) m) m0 (points s)
         manhattan :: Num a => (a, a) -> (a, a) -> a
         manhattan (x0,y0) (x1,y1) = abs (x1 - x0) + abs (y1 - y0)

switchLights :: Ord a => World a -> World a
switchLights w = w{lights = newLights, streetLut = newLut}
   where newLights = map switchLight (lights w)
         switchLight l = l{state = ls}
            where ls = case state l of (Green, i)  -> (Yellow, i)
                                       (Yellow, i) -> (Green, (i+1) `mod` length (crossingStreets l))
         newLut = foldr (\l -> Map.adjust (updatePoint l) (lightX l, lightY l)) (streetLut w) newLights
         updatePoint l _ = (d, Just (fst (state l)), s')
            where s' = crossingStreets l !! snd (state l)
                  d  = case lookup (lightX l, lightY l) (points s') of Just d' -> d'
                                                                       Nothing -> error "switchLights: point not in street"

