module Main (main) where

import qualified Car as Car
import Interpreter.Golog
import Interpreter.Tree
import Interpreter.TreeUtil
import Util.NativePSO
import qualified RSTC.BAT as BAT
import qualified RSTC.Obs as Obs
import RSTC.Progs

instance (Show a) => Show (BAT.Prim a) where
   show (BAT.Wait t) = "Wait " ++ (show t)
   show (BAT.Accel b q) = "Accel " ++ (show b) ++ " " ++ (show q)
   show (BAT.LaneChange b l) = "LaneChange " ++ (show b) ++ " " ++ (show l)
   show (BAT.Init e) = "Init " ++ (show (Obs.time e))
   show (BAT.Match e) = "Match " ++ (show (Obs.time e))
   show BAT.Abort = "Abort"
   show BAT.NoOp = "NoOp"
   show (BAT.Start b s) = "Start " ++ (show b) ++ " " ++ s
   show (BAT.End b s) = "End " ++ (show b) ++ " " ++ s

instance Show Finality where
   show Final = "Final"
   show Nonfinal = "Nonfinal"

instance (Show a) => Show (Atom a) where
   show (Prim a)  = "Prim(" ++ (show a) ++ ")"
   show (PrimF _) = "PrimF(...)"
   show (Test _)  = "Test(...)"

instance (Show a) => Show (PseudoAtom a) where
   show (Atom a) = "Atom(" ++ (show a) ++ ")"
   show (Complex p) = "Complex(" ++ (show p) ++ ")"

instance (Show a) => Show (Prog a) where
   show (Seq p1 p2) = "Seq(" ++ (show p1) ++ " " ++ (show p2) ++ ")"
   show (Nondet p1 p2) = "Nondet(" ++ (show p1) ++ " " ++ (show p2) ++ ")"
   show (Conc p1 p2) = "Conc(" ++ (show p1) ++ " " ++ (show p2) ++ ")"
   show (Star p) = "Star(" ++ (show p) ++ ")"
   show (Pick _ x0 p) = "Pick(MaxiF x0 " ++ (show (p x0)) ++ ")"
   show (PseudoAtom p) = "PseudoAtom(" ++ (show p) ++ ")"
   show Nil = "nil"

instance (Show v, Show a) => Show (Tree v a) where
   show = showTree 0

instance (Show a) => Show (Sit a) where
   show s = show (sit2list s)
   --show S0 = "S0"
   --show (Do a s) = "Do(" ++ (show a) ++ ", " ++ (show s) ++ ")"

showTree :: (Show v, Show a) => Int -> Tree v a -> String
showTree n _ | n > 25 = (replicate (2*n) ' ') ++ "...\n"
showTree n Empty = (replicate (2*n) ' ') ++ "Empty\n"
showTree n (Leaf x) = (replicate (2*n) ' ') ++ "Leaf " ++ (show x) ++ "\n"
showTree n (Parent x t) = (replicate (2*n) ' ') ++ "Parent " ++ (show x) ++ "\n" ++ (showTree (n+1) t)
showTree n (Branch t1 t2) = (replicate (2*n) ' ') ++ "Branch\n" ++ (showTree (n+1) t1) ++ (showTree (n+1) t2)
showTree n (Sprout _ _) = (replicate (2*n) ' ') ++ "Sprout g, <unknown tree>\n"


sit2list :: Sit a -> [a]
sit2list S0 = []
sit2list (Do a s) = (sit2list s) ++ [a]


{-
filterEmpty :: Tree v a -> Tree v a
filterEmpty Empty          = Empty
filterEmpty t @ (Leaf _)   = t
filterEmpty (Parent x t1) = case filterEmpty t1
   of Empty -> Leaf x
      t2    -> Parent x t2
filterEmpty (Branch t1 t2) = case (filterEmpty t1, filterEmpty t2)
   of (Empty, Empty) -> Empty
      (Empty, t)     -> t
      (t, Empty)     -> t
      (t3, t4)       -> Branch t3 t4
filterEmpty (Sprout _ _)   = error "Main.filterEmpty: Sprout"
-}


data Prim = A | B | C | D | E Double deriving Show

instance BAT Prim where
   poss D _ = False
   poss _ _ = True

   reward A s = case s of Do A _ -> 0
                          _      -> 0
   reward B s = case s of Do B _ -> 1
                          _      -> 0
   reward C s = case s of Do C _ -> 2
                          _      -> 0
   reward D s = case s of Do D _ -> 3
                          _      -> 0
   reward (E x) _ = max 0 (-x*x+100)


-- Ist eh falsch, doch nicht von value!
-- Achso, doch, ist ja value 0. Ich Flachpfeife.
--depth t = snd (value 0 t)


main :: IO ()
main =
   let   a = PseudoAtom (Atom (Prim A))
         b = PseudoAtom (Atom (Prim B))
         c = PseudoAtom (Atom (Prim C))
         --d = PseudoAtom (Atom (Prim D))
         e x = PseudoAtom (Atom (Prim (E x)))
         p1 = ((a `Nondet` b `Nondet` c) `Seq` ((a `Seq` a `Seq` c) `Conc` (b `Seq` b `Seq` c))) `Nondet` Star(a `Seq` c `Seq` c `Seq` c `Seq` c)
         p2 = ((a `Nondet` b) `Seq` ((a `Seq` a `Seq` c) `Conc` (b `Seq` b `Seq` c)))
         ppick p = Pick (\f -> pso 10 25 5 defaultParams (-20, 20) (Max (fst.f))) 10 p
         p3 = ppick e
         p4 = (ppick e) `Seq` (ppick e)
         p5 = ppick (\x -> (e x) `Seq` (ppick e))
         p6 = ppick (\x -> (e x) `Seq` (ppick (\y -> e (x*y))))
         --p = Star(a)
         t1 = tree p1 S0 0.0 0
         t2 = tree p2 S0 0.0 0
         exec n t' = trans ((depth t') + n) t'
         candProg = tailgate Car.H Car.D
   in do
{-
         putStrLn ((show . cutoff 2) t2)
         putStrLn "-------------------------------------------------------\n"
         putStrLn (maybe "nothing" (show . cutoff 3) (exec 0 t2))
         putStrLn "-------------------------------------------------------\n"
         putStrLn (maybe "nothing" (show . cutoff 3) (exec 1 t2))
         putStrLn "-------------------------------------------------------\n"
         putStrLn (maybe "nothing" (show . cutoff 3) (exec 2 t2))
         putStrLn "-------------------------------------------------------\n"
         putStrLn (maybe "nothing" (show . cutoff 3) (exec 3 t2))
         putStrLn "-------------------------------------------------------\n"
         putStrLn ((show . cutoff 10) t1)
         putStrLn "-------------------------------------------------------\n"
         putStrLn (maybe "nothing" (show . cutoff 10) (exec 100000 t1))
         putStrLn "-------------------------------------------------------\n"
         mapM_ (\i -> putStrLn (show i ++ ": " ++ show (do1 i p2 S0))) [0..9]
         putStrLn "-------------------------------------------------------"
         mapM_ (\i -> putStrLn ("Pick one: " ++ show i ++ ": " ++ show (do1 i p3 S0))) [0..5]
         putStrLn "-------------------------------------------------------"
         mapM_ (\i -> putStrLn ("Pick seq: " ++ show i ++ ": " ++ show (do1 i p4 S0))) [0..5]
         putStrLn "-------------------------------------------------------"
         mapM_ (\i -> putStrLn ("Pick nested: " ++ show i ++ ": " ++ show (do1 i p5 S0))) [0..5]
         putStrLn "-------------------------------------------------------"
         mapM_ (\i -> putStrLn ("Pick nested 2: " ++ show i ++ ": " ++ show (do1 i p6 S0))) [0..5]
         putStrLn "-------------------------------------------------------"
-}
         --mapM_ (putStrLn . show) (take 30 Obs.observations)
         --putStrLn "-------------------------------------------------------"
         --mapM_ (\i -> putStrLn ((show . cutoff i) (tree (obsprog Obs.observations) S0 0.0 0))) [0..30]
         --putStrLn "-------------------------------------------------------\n"
         mapM_ (putStrLn . show) (do3 4 (Conc (obsprog (take 30 Obs.observations)) (candProg)) S0)
         putStrLn "-------------------------------------------------------"
{-
         mapM_ (putStrLn . show) (map (maybe Nothing $ (\x -> Just
               ( x
               , Obs.time x
               , map (Obs.lane x) [Car.B,Car.D,Car.H]
               , map (uncurry (Obs.ntg x)) [(x,y) | x <- [Car.B,Car.D,Car.H], y <- [Car.B,Car.D,Car.H]]
               , map (uncurry (Obs.ttc x)) [(x,y) | x <- [Car.B,Car.D,Car.H], y <- [Car.B,Car.D,Car.H]]
               ))) (take 30 observations))
-}
--         putStrLn "-------"
--         putStrLn (show (cutoff 30 (trans 14 t1)))
--         putStrLn "-------"
--         putStrLn (show (cutoff 30 (trans 24 (trans 14 t1))))
--         putStrLn "-------"
--         putStrLn (show (cutoff 30 (trans 28 (trans 24 (trans 14 t1)))))
--         putStrLn "-------"
--         putStrLn (show (cutoff 30 (trans 42 (trans 24 (trans 24 (trans 14 t1))))))
--         putStrLn "-------"
--         putStrLn (show (cutoff 7 (trans 3 t2)))
--         --putStrLn "-------"
--         --putStrLn (show (toList (cutparents t)))

