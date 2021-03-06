{-# LANGUAGE GADTs #-}
{-# LANGUAGE TypeFamilies #-} 
{-# LANGUAGE Rank2Types #-}

-- | Golog interpreter with transition semantics, decision theory and
-- concurrency.
-- Nondeterministic construct like branch, iteration, pick, and concurrency by
-- interleaving are resolved by opting for the choice that leads to the highest
-- rewarded situation.
--
-- The semantics is based on [1], but not that close to the formal
-- definition:
--
-- * Programs are decomposed into a next atomic action and the respective
--   remaining program. This is done by the functions private functions 'next'
--   and and 'next'' as in [1].
--
-- * The tree of reachable situations is constructed (lazily). This is done by
--   decomposing the program, executing the next atomic action, and continuing
--   this recursively for the remaining program in 'tree'.
--
-- \[1\] <http://kbsg.rwth-aachen.de/~schwering/CogRob-2012/paper.pdf>

module Golog.Old.Interpreter (BAT(..),
                              Reward, Depth, OptiF, Finality(..),
                              Atom(..), PseudoAtom(..), Prog(..),
                              Conf, SitTree, Grown, Ungrown,
                              force, best, isFinal, tree,
                              trans, do1, do2, do3,
                              sit, rew, depth, final, value) where
    
import Golog.Old.Tree
import Prelude hiding (max)

type Reward = Double

-- | Basic action theory for an action type 'a'.
--
-- The situation type 'Sit' is part of the BAT in order to allow the BAT use
-- progression instead of regression.
-- For /regression/, one usually defines @data Sit a = S0 | Do a (Sit a)@ in the
-- instance @BAT a@.
-- Then 's0' and 'do_' should be defined as 'S0' and 'Do', respectively.
-- The fluents then need to be the successor state axioms.
-- For /progression/, 'Sit' could be defined as a set map of values.
-- In this case 's0' could return a map containing the initial values and 'do_'
-- should compute the new map of values.
--
-- 'poss' corresponds to Reiter's /Poss/ predicate and should return 'True' iff
-- the action is executable in the given situation.
-- 'reward' indicates how good an action is in a situation.
class BAT a where
   data Sit a :: *
   s0         :: Sit a
   do_        :: a -> Sit a -> Sit a
   poss       :: a -> Sit a -> Bool
   reward     :: a -> Sit a -> Reward

type Conf a = (Sit a, Reward, Depth, Finality)
type SitTree a b = Tree a (Conf b) (Conf b)


data Atom a = Prim a
            | PrimF (Sit a -> a)
            | Test (Sit a -> Bool)

data PseudoAtom a = Atom (Atom a)
                  | Complex (Prog a)

data Prog a where
   Seq        :: Prog a -> Prog a -> Prog a
   Nondet     :: Prog a -> Prog a -> Prog a
   Conc       :: Prog a -> Prog a -> Prog a
   Star       :: Prog a -> Prog a
   Pick       :: Ord v => (SitTree Grown a -> v) -> OptiF u v -> (u -> Prog a) -> Prog a
   PseudoAtom :: PseudoAtom a -> Prog a
   Nil        :: Prog a

data Finality = Final
              | Nonfinal


-- | Computes the next pseudo-atomic actions and the remainders.
-- Pseudo-atomic means that the next action may be 'Complex' one.
--
-- The returned tree may contain the following kinds of nodes:
--
-- * 'Empty' for 'Nil'.
--
-- * 'Leaf' for decompositions.
--
-- * 'Branch' when there is nondeterminism.
--
-- * 'Sprout' for each pick.
--
-- Note that 'Parent' nodes do not occur.
next :: Prog a -> Tree Ungrown (Conf a) (PseudoAtom a, Prog a)
next (Seq p1 p2)       = let t1 = fmap (\(c, p') -> (c, Seq p' p2)) (next p1)
                         in if final' p1 then branch (next p2) t1 else t1
next (Nondet p1 p2)    = branch (next p1) (next p2)
next (Conc p1 p2)      = branch (fmap (\(c, p') -> (c, Conc p' p2)) (next p1))
                                (fmap (\(c, p') -> (c, Conc p1 p')) (next p2))
next (Pick val maxi p) = Sprout val maxi (\x -> next (p x))
next (Star p)          = fmap (\(c, p') -> (c, Seq p' (Star p))) (next p)
next (PseudoAtom c)    = Leaf (c, Nil)
next Nil               = Empty


-- | Indicates whether or not a program may be final.
final' :: Prog a -> Bool
final' (Seq p1 p2)              = final' p1 && final' p2
final' (Nondet p1 p2)           = final' p1 || final' p2
final' (Conc p1 p2)             = final' p1 && final' p2
final' (Pick _ _ p)             = final' (p undefined)
final' (Star _)                 = True
final' (PseudoAtom (Atom _))    = False
final' (PseudoAtom (Complex p)) = final' p
final' Nil                      = True


-- | Computes the next atomic actions and the remainders.
-- This is done by simply re-decomposing the 'Complex' actions returned by
-- 'next'.
-- The tree structure is the same as for 'next'.
next' :: Prog a -> Tree Ungrown (Conf a) (Atom a, Prog a)
next' p = lmap h (next p)
   where h ((Atom c), p')      = Leaf (c, p')
         h ((Complex p''), p') = next' (Seq p'' p')


-- | Determines the infinite tree of situations induced by a program.
-- The tree starts off at the given situation with the given reward and depth.
-- Both reward and depth are incremented from that point on.
--
-- The returned tree may contain the following kinds of nodes:
--
-- * 'Empty' when an primitive or test action failed.
--
-- * 'Parent' for reached configurations.
--   The configuration contains the situation term, its reward, the depth
--   (number of transitions to this configuration), and its finality.
--   The subtree indicates how execution may go on from this configuration.
--
-- * 'Branch' when there is nondeterminism.
--
-- * 'Sprout' for each pick.
--
-- Note that 'Leaf' nodes to not occur as they are replaced with 'Parent' and/or
-- 'Empty' nodes.
tree :: BAT a => Prog a -> Sit a -> Reward -> Depth -> SitTree Ungrown a
tree p s r d = let f = if final' p then Final else Nonfinal
               in Parent (s, r, d, f) (lmap transAtom (next' p))
   where transAtom (Prim a, p')  | poss a s  = let s' = do_ a s
                                                   r' = r + (reward a s)
                                                   d' = d + 1
                                               in tree p' s' r' d'
                                 | otherwise = Empty
         transAtom (PrimF b, p')             = transAtom (Prim (b s), p')
         transAtom (Test e, p')  | e s       = tree p' s r (d+1)
                                 | otherwise = Empty


-- | Computes the maximum achievable reward and depth in a tree up to a certain
-- depth.
--
-- Note that in the tree constructed by 'tree' 'Parent' nodes may have
-- grandchildren with the same depth in case they represent a final
-- configuration. For this reason we even have to inspect the subtree of the
-- 'Parent' node when we've reached the maximum depth.
--
-- The lookahead argument specifies the search depth up to which value is
-- computed.
--
-- This function expects that 'Sprout' nodes have been resolved already (e.g.,
-- using 'pickbest'). Otherwise 'Sprout's yield errors.
value :: BAT a => Depth -> SitTree Grown a -> (Reward, Depth)
value l t = val (best def max fnl l t)
   where val (_, r, d, _) = (r, d)
         fnl (_, _, _, f) = isFinal f
         max              = maxBy (cmpBy val)
         def              = (s0, 0, 0, Nonfinal)


-- | Transitions to the next best configuration is there one.
-- Otherwise 'Nothing' is returned.
--
-- At 'Parent' nodes it stops unless the subtree has a higher value.
-- At 'Branch' nodes it opts for the higher values alternative.
--
-- The lookahead argument specifies the search depth up to which value is
-- computed.
trans :: BAT a => Depth -> SitTree Grown a -> Maybe (SitTree Grown a)
trans l (Parent (_, v, d, f) t) | not (isFinal f)    = trans' t
                                | (v, d) < value l t = trans' t
                                | otherwise          = Nothing
   where trans' Empty             = Nothing
         trans' t' @ (Parent _ _) = Just t'
         trans' (Branch t1 t2)    = trans' (maxBy (cmpBy (value l)) t1 t2)
         trans' (Leaf _)          = error "Golog.trans': Leaf"
trans _ Empty           = error "Golog.trans: Empty"
trans _ (Leaf _)        = error "Golog.trans: Leaf"
trans _ (Branch _ _)    = error "Golog.trans: Branch"


-- | Returns the function-maximizing element.
maxBy :: (a -> a -> Ordering) -> a -> a -> a
maxBy cmp x y | cmp x y == GT = x
              | otherwise     = y


-- | Returns the function-maximizing element.
cmpBy :: Ord b => (a -> b) -> a -> a -> Ordering
cmpBy f x y = compare (f x) (f y)


-- | The current configurations situation term.
sit :: SitTree a b -> Sit b
sit (Parent (s, _, _, _) _) = s
sit Empty                   = error "Golog.sit: Empty"
sit (Leaf _)                = error "Golog.sit: Leaf"
sit (Branch _ _)            = error "Golog.sit: Branch"
sit (Sprout _ _ _)          = error "Golog.sit: Sprout"


-- | The current configurations reward.
rew :: SitTree a b -> Reward
rew (Parent (_, r, _, _) _) = r
rew Empty                   = error "Golog.rew: Empty"
rew (Leaf _)                = error "Golog.rew: Leaf"
rew (Branch _ _)            = error "Golog.rew: Branch"
rew (Sprout _ _ _)          = error "Golog.rew: Sprout"


-- | The current configurations depth.
depth :: SitTree a b -> Depth
depth (Parent (_, _, d, _) _) = d
depth Empty                   = error "Golog.depth: Empty"
depth (Leaf _)                = error "Golog.depth: Leaf"
depth (Branch _ _)            = error "Golog.depth: Branch"
depth (Sprout _ _ _)          = error "Golog.depth: Sprout"


-- | Indicates whether the execution /might/ stop in this configuration.
-- Whether 'trans' really stops additionally depends on whether further
-- execution, if possible, yields a higher reward.
--
-- To avoid confusion, we probably should not export this function.
final :: SitTree a b -> Bool
final (Parent (_, _, _, f) _) = isFinal f
final Empty                   = error "Golog.final: Empty"
final (Leaf _)                = error "Golog.final: Leaf"
final (Branch _ _)            = error "Golog.final: Branch"
final (Sprout _ _ _)          = error "Golog.final: Sprout"


-- | True iff Final.
isFinal :: Finality -> Bool
isFinal Final    = True
isFinal Nonfinal = False


-- | Executes a program in a situation and returns the resulting situation.
-- Additionally the reward and depth are returned.
-- If the execution fails, 'Nothing' is returned.
--
-- The lookahead argument specifies the search depth up to which value is
-- computed.
do1 :: BAT a => Depth -> Prog a -> Sit a -> Maybe (Sit a, Reward, Depth)
do1 l p s = do2 l (force (tree p s 0 0))


-- | Searches for the best final reachable situation in the tree.
-- Additionally the reward and depth are returned.
-- If none is found, 'Nothing' is returned.
--
-- The lookahead argument specifies the search depth up to which value is
-- computed.
do2 :: BAT a => Depth -> SitTree Grown a -> Maybe (Sit a, Reward, Depth)
do2 l t | final t   = Just (sit t, rew t, depth t)
        | otherwise = trans l t >>= do2 l


-- | Executes a program in a situation and returns all situations on the way.
-- If there is none, the list is infinite.
-- Additionally the reward and depth are returned.
--
-- The lookahead argument specifies the search depth up to which value is
-- computed.
do3 :: BAT a => Depth -> Prog a -> Sit a -> [(Sit a, Reward, Depth)]
do3 l p s = do4 l (force (tree p s 0 0))


-- | The list of situations encountered on the search for the best final one. 
-- If there is none, the list is infinite.
-- Additionally the reward and depth are returned.
--
-- The lookahead argument specifies the search depth up to which value is
-- computed.
do4 :: BAT a => Depth -> SitTree Grown a -> [(Sit a, Reward, Depth)]
do4 l t | final t   = [(sit t, rew t, depth t)]
        | otherwise = case trans l t of
                           Nothing -> []
                           Just t' -> (sit t', rew t', depth t') : do4 l t'

