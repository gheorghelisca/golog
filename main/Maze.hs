{-# LANGUAGE TypeFamilies, FlexibleInstances, FlexibleContexts #-}
{-# LANGUAGE EmptyDataDecls #-}

module Main (main) where

import Prelude hiding (Left, Right)
import Data.List (sortBy)
import Interpreter.Golog2
import Interpreter.Golog2Util
import qualified Util.Random as Random


{- Maze functions: -}

data Point = P Int Int deriving (Show, Eq)

roomSize, roomHeight, roomWidth :: Int
roomSize   = 10
roomHeight = roomSize
roomWidth  = roomHeight

startPos :: Point
startPos = P 0 0

goalPos :: Point
goalPos = P (2 * roomWidth - 1) (2 * roomHeight - 1)

inMaze :: Point -> Bool
inMaze (P x y) = 0 <= x && x < 2 * roomWidth &&
                 0 <= y && y < 2 * roomHeight

atUpperWall, atLowerWall, atLeftWall, atRightWall :: Int -> Bool
atUpperWall y = y     `mod` roomHeight == 0
atLowerWall y = (y+1) `mod` roomHeight == 0
atLeftWall  x = x     `mod` roomWidth  == 0
atRightWall x = (x+1) `mod` roomWidth  == 0

atVerticalDoor, atHorizontalDoor :: Point -> Bool
atVerticalDoor   (P x y) = x `mod` roomWidth  == roomWidth  `div` 2 && abs (y - roomHeight) <= 1
atHorizontalDoor (P x y) = y `mod` roomHeight == roomHeight `div` 2 && abs (x - roomWidth)  <= 1

up', down', left', right' :: Point -> Point
up'     (P x y) = P x (y - 1)
down'   (P x y) = P x (y + 1)
left'   (P x y) = P (x - 1) y
right'  (P x y) = P (x + 1) y

isValidNeighborOf :: Point -> Point -> Bool
isValidNeighborOf (P x' y') p@(P x y)
   | x' == x   && y' == y-1 = not (atUpperWall y) || atVerticalDoor p
   | x' == x   && y' == y+1 = not (atLowerWall y) || atVerticalDoor p
   | x' == x-1 && y' == y   = not (atLeftWall  x) || atHorizontalDoor p
   | x' == x+1 && y' == y   = not (atRightWall x) || atHorizontalDoor p
   | otherwise              = False

dist :: Point -> Point -> Double
dist = distEuclidean

distEuclidean :: Point -> Point -> Double
distEuclidean (P x1 y1) (P x2 y2) = sqrt (fromIntegral $ x*x + y*y)
   where x = x1 - x2
         y = y1 - y2

distManhattan :: Point -> Point -> Double
distManhattan (P x1 y1) (P x2 y2) = fromIntegral $ abs (x1 - x2) + abs (y1 - y2)

data Prim a = Up | Down | Left | Right deriving (Show, Eq)


{- Regressive BAT: -}

data Regr

class DTBAT (Prim a) => MazeBAT a where
   pos          :: Sit (Prim a) -> Point
   unvisited    :: Point -> Sit (Prim a) -> Bool
   visited      :: Sit (Prim a) -> [Point]
   memory       :: Sit (Prim a) -> [Prim a]
   randomSupply :: MazeBAT a => Sit (Prim a) -> Random.Supply
   rewardSum    :: Sit (Prim a) -> Reward

   unvisited p s = p `notElem` visited s

instance BAT (Prim Regr) where
   data Sit (Prim Regr) = S0 | Do (Prim Regr) (Sit (Prim Regr)) deriving Show

   s0  = S0

   do_ = Do

   poss a s = let p  = pos s
                  p' = newPos a p
              in p' `isValidNeighborOf` p && unvisited p' s

instance DTBAT (Prim Regr) where
   reward a s = (dist startPos goalPos - dist (newPos a (pos s)) goalPos)**2 -
                (dist startPos goalPos - dist (pos s) goalPos)**2

instance MazeBAT Regr where
   pos = pos' . memory
      where pos' []     = startPos
            pos' (a:as) = newPos a (pos' as)

   visited s = scanr (\f p -> f p) startPos (map newPos (memory s))

   memory S0       = []
   memory (Do a s) = a : memory s

   rewardSum S0       = 0
   rewardSum (Do a s) = rewardSum s + reward a s

   randomSupply s = foldr (\f rs -> f rs) startRandomSupply (map newRandomSupply (memory s))


{- Progressive BAT: -}

data Progr

instance BAT (Prim Progr) where
   data Sit (Prim Progr)       = Sit [Point] Reward [Prim Progr] Random.Supply

   s0                          = Sit [startPos] 0 [] startRandomSupply

   do_  a s@(Sit ps@(p:_) r m rs) = Sit (newPos a p : ps)
                                        (r + reward a s)
                                        (a : m)
                                        (newRandomSupply a rs)
   do_  a s@(Sit []       _ _ _)  = error "do_: empty point history"

   poss a s@(Sit (p:_) r m _)  = let p' = newPos a p
                                 in p' `isValidNeighborOf` p && unvisited p' s
   poss a s@(Sit []    _ _ _)  = error "poss: empty point history"

instance DTBAT (Prim Progr) where
   reward a s = (improv - penalty a (memory s) / 9) / normf
      where oldRem = dist goalPos (pos s)
            newRem = dist goalPos (newPos a (pos s)) 
            improv = oldRem - newRem
            normf  = fromIntegral $ sitlen s + 1
            penalty a []     = 0
            penalty a (a':_) = case (a,a') of (Up,Up)       -> 0
                                              (Up,Down)     -> 2
                                              (Up,_)        -> 1
                                              (Down,Down)   -> 0
                                              (Down,Up)     -> 2
                                              (Down,_)      -> 1
                                              (Left,Left)   -> 0
                                              (Left,Right)  -> 2
                                              (Left,_)      -> 1
                                              (Right,Right) -> 0
                                              (Right,Left)  -> 2
                                              (Right,_)     -> 1
   --dist (pos s) goalPos - dist (newPos a (pos s)) goalPos
   --abs (dist startPos goalPos - dist (newPos a (pos s)) goalPos)**1 -
   --abs (dist startPos goalPos - dist (pos s) goalPos)**1

instance MazeBAT Progr where
   pos (Sit (p:_) _ _ _) = p
   pos (Sit _     _ _ _) = error "pos: empty point history"

   visited (Sit ps _ _ _) = ps

   memory (Sit _ _ m _) = m

   rewardSum (Sit _ r _ _) = r

   randomSupply (Sit _ _ _ rs) = rs


{- Common BAT functions: -}

newPos :: (Prim a) -> Point -> Point
newPos Up    p = up' p
newPos Down  p = down' p
newPos Left  p = left' p
newPos Right p = right' p

sitlen :: MazeBAT a => Sit (Prim a) -> Int
sitlen = length . memory

startRandomSupply :: Random.Supply
startRandomSupply = Random.init 3

newRandomSupply :: Prim a -> Random.Supply -> Random.Supply
newRandomSupply Up    rs = Random.shuffle  7 $ snd $ Random.random $ rs
newRandomSupply Down  rs = Random.shuffle 13 $ snd $ Random.random $ rs
newRandomSupply Left  rs = Random.shuffle 19 $ snd $ Random.random $ rs
newRandomSupply Right rs = Random.shuffle 31 $ snd $ Random.random $ rs

random :: MazeBAT a => Sit (Prim a) -> Int
random s = fst $ Random.random (randomSupply s)

up :: MazeBAT a => Sit (Prim a) -> Prim a
up s = opt (Down,Left,Right,Up) s

down :: MazeBAT a => Sit (Prim a) -> Prim a
down s = opt (Up,Left,Right,Down) s

left :: MazeBAT a => Sit (Prim a) -> Prim a
left s = opt (Up,Down,Right,Left) s

right :: MazeBAT a => Sit (Prim a) -> Prim a
right s = opt (Up,Down,Left,Right) s

opt :: MazeBAT a => (Prim a,Prim a,Prim a,Prim a) -> Sit (Prim a) -> (Prim a)
opt (a0,a1,a2,a3) s |  0 <= pct && pct < 10 && poss a0 s = a0
                    | 10 <= pct && pct < 30 && poss a1 s = a1
                    | 30 <= pct && pct < 50 && poss a2 s = a2
                    | otherwise                          = a3
   where r   = random s
         pct = r `mod` 100

lookahead :: Depth
lookahead = 5

main :: IO ()
main = do
   let prog :: Prog (Prim Progr)
       prog  = star (Nondet [ primf up
                            , primf down
                            , primf left
                            , primf right]) `Seq`
               test (\s -> pos s == goalPos)
       tree  = treeDT lookahead prog s0
       confs = do2 tree
   putStrLn $ show $ startPos
   putStrLn $ show $ goalPos
   mapM_ (\s -> putStrLn $ (if pos s == goalPos then " *** " else " ... ") ++
            show (pos s, dist goalPos (pos s), rewardSum s
                  --,case s of Do a s' -> (pos s `elem` visited s', visited s')
                  )) $ map sit confs
   let s = sit $ last $ confs
   putStrLn $ "Actions: " ++ show (sitlen s)
   draw s

draw :: MazeBAT a => Sit (Prim a) -> IO ()
draw s = draw' 0 0 visPs
   where --allPs = [(x,y) | x <- [0..2*roomWidth], y <- [0..2*roomHeight]]
         visPs = sortBy cmp (visited s)
         cmp (P x1 y1) (P x2 y2) = compare (y1,x1) (y2,x2)
         draw' :: Int -> Int -> [Point] -> IO ()
         draw' _ _ []            = putChar '\n'
         draw' x y ps@((P x' y') : ps')
            | y == y' && x == x' = putChar 'X'  >> draw' (x+1) y ps'
            | y == y' && x <  x' = putChar ' '  >> draw' (x+1) y ps
            | y <  y'            = putChar '\n' >> draw' 0 (y+1) ps
            | otherwise          = error $ "draw' "++ show (x,y) ++" "++ show (x',y')
