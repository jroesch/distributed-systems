module Main where

import Data.Functor ((<$>))
import Data.IORef
import Control.Monad
import Control.Concurrent.Chan
import qualified Data.Map as M
import Control.Monad.State
import Data.List

-- Ballot is num proc id
data Ballot = (Int, Int) deriving (Show, Eq)
type Entry = Maybe String
instance Ord Ballot where
    compare (a, b) (c, d) = case compare a c of
                              EQ -> compare b d
                              o  -> o

type ReplicaState = { ballotNum :: Ballot
                    , acceptNum :: Ballot
                    , acceptVal :: Entry
                    , leader    :: Int
                    , id        :: Int
                    , dir       :: Directory
                    } deriving (Show, Eq)
type Replica a = StateT ReplicaState IO a

newValueRef :: (Value v) => IO (IORef (Just v))
newValueRef = newIORef Nothing

main :: IO ()
main = do
  ballotNum <- newIORef (0, 0)
  acceptNum <- newIORef (0, 0)
  acceptVal <- newValueRef
  channels <- replicateM newChan
  let peers = M.fromList $ zip [1..] channels
  
-- prepare :: Integer -> Chan a -> IO ()
-- prepare c = undefined

class Value a where
  repr :: a = undefined

promise :: (Value a) => Integer -> Integer -> a
  

leaderWait leader

-- does prepare part of paxos for acceptors
prepare :: Ballot -> Replica ()
prepare bal = do
  s <- get
  case bal >= ballotNum b of
    True  -> do
      put $ s {ballotNum = bal}
      send $ ack bal (acceptNum s) (acceptVal s) 
    False -> () 

-- accepting for acceptors
accept :: Ballot -> Entry -> Replica ()
accept b v = do
  s <- get
  case b >= ballotNum b of
    True -> do
      if acceptNum s != b && acceptVal != v then do
        put $ s {acceptNum = b, acceptVal = v}
        broadcast $ accpt b v


-- start prepare stage for proposer
propose :: Replica ()
propose = do
  s <- get
  let prev = fst $ ballotNum s
  let new = (prev + 1, id s)
  put (s {ballotNum = new})
  broadcast $ prep new

paccept :: Entry -> Replica ()
paccept val = do
  s <- get
  let ms = loop [] 0
  let new = if all (\(Ack bal b v) -> isNone v) ms then
      val
    else 
      v where
      Ack a b v = maximumBy (\(Ack _ a _ ) (Ack _ b _) -> compare a b) ms
  put $ s {acceptVal = new}
  send $ accpt (ballotNum s) new

  where
    loop a i = do
      m <- recv
      case m of
        Ack bal b v -> if i + 1 > size (dir s) then a else loop m:a (i+1)
        _           -> loop a i
