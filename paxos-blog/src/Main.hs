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
                    , acceptedM :: ([Message], Int)
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

acceptor :: Message -> Replica ()
acceptor msg = do
    s <- get
    case msg of
      Prepare bn | bn >= ballotNum s -> do
        put $ s {ballotNum = bn}
        send $ Ack bn (acceptNum s) (acceptVal s)
      Accept b v | b >= ballotNum b -> do
        -- ensure we dont send accept message multiple times
        if acceptNum s != b && acceptVal != v then do
          put $ s {acceptNum = b, acceptVal = v}
          broadcast $ Accept b v
      Decide 
      _ -> ()

proposer :: String -> Message -> Replica ()
proposer value msg = do
    s <- get
    case msg of
      Ack bn b v | bn == ballotNum s -> do
        let (oldL, oldC) = acceptedM s
        let newL = msg : oldL
        let newC = oldC + 1
        if newC > size (dir s) then do
          let new = if all (\(Ack bal b v) -> isNone v) newL then
              value
            else 
              v where
                Ack a b v = maximumBy (\(Ack _ a _ ) (Ack _ b _) -> compare a b) newL
          put $ s {acceptVal = new}
          send $ accpt (ballotNum s) new
        else put $ s {acceptedM = (newL, newC)}
      _ -> ()
