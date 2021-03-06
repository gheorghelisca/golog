module RSTC.Car where

import Data.Ix
import System.IO.Unsafe

data Lane = LeftLane | RightLane deriving (Eq, Enum, Show)

data Car = A | B | C | D | E | F | G | H deriving (Bounded, Enum, Eq, Ix, Ord, Show)

cars :: [Car]
--cars = [B .. H]
--cars = [D,H]
cars = [B,D,H]


debug :: (Show a) => a -> a
debug x = unsafePerformIO (do putStrLn (show x)
                              return x)


debug' :: (Show a) => String -> a -> a
debug' s x = unsafePerformIO (do putStrLn (s ++ ": " ++ (show x))
                                 return x)

