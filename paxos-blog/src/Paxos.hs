module Paxos where

import Control.Monad.State
import Data.Maybe
import qualified Data.Map as M
import Data.List
import Data.Functor

import Paxos.Message
import qualified Paxos.Directory as D

data PaxosState = PaxosState { 
    ballotNum :: Ballot
  , acceptNum :: Ballot
  , acceptVal :: Value
  -- , leader    :: Bool
  , ident     :: Int
  , dir       :: D.Directory
  , ackM      :: ([Message], Int) -- clean this up
  , acceptedM :: Int -- clean this up
  } deriving (Show, Eq)

type PaxosInstance a = StateT PaxosState IO a

initialState :: D.Directory -> D.Pid -> PaxosState
initialState d pid = 
  PaxosState { 
    ballotNum = Ballot (0, pid),
    acceptNum = Ballot (0, 0),
    acceptVal = Nothing,
    -- leader    =
    ident     = pid, 
    dir       = d,
    ackM      = ([], 0),
    acceptedM = 0
  }

broadcastP :: Message -> PaxosInstance ()
broadcastP m = do
  s <- get
  lift $ D.broadcast (dir s) m

sendP :: D.Pid -> Message -> PaxosInstance ()
sendP p m = do
  s <- get
  lift $ D.send (dir s) p m

propose :: PaxosInstance ()
propose = do
  s <- get
  if ident s == 1 then do
    let Ballot (prev, _) = ballotNum s
    let new = Ballot (prev + 1, ident s)
    put (s {ballotNum = new})
    broadcastP $ Prepare new
  else
    return ()

maxAck :: [Message] -> Value -- bad assumptions here, that all message will match this pattern
maxAck acks = let Ack a b v = maximumBy (\(Ack _ a _ ) (Ack _ b _) -> compare a b) acks in v

acceptor :: Message -> PaxosInstance ()
acceptor msg = do
    s <- get
    case msg of
      Prepare bn | bn >= ballotNum s -> do
        put $ s {ballotNum = bn}
        broadcastP $ Ack bn (acceptNum s) (acceptVal s)
      Accept b v | b >= ballotNum s -> do -- Fix maybe code here
        -- ensure we dont send accept message multiple times
        if (acceptNum s) /= b then do
          put $ s {acceptNum = b, acceptVal = v}
          new <- get
          broadcastP $ Accept b v
        else return ()
      Decide v -> return () -- placeholder
      otherwise -> return ()

proposer :: String -> Message -> PaxosInstance ()
proposer value msg = do
    s <- get
    case msg of
      Ack bn b v | bn == ballotNum s -> do
        let (oldL, oldC) = ackM s
        let newL = msg : oldL
        let newC = oldC + 1
        if newC > div (M.size (dir s)) 2 && acceptNum s /= bn
          then do
            let new = if all (\(Ack bal b v) -> isNothing v) newL 
                        then Just value
                        else maxAck newL
            put $ s { acceptVal = new, acceptNum = bn }
            broadcastP $ Accept (ballotNum s) new
          else put $ s {ackM = (newL, newC)} -- clean up acceptM
      Accept b v -> do
        let new = acceptedM s + 1
        put $ s {acceptedM = new}
        if new == M.size (dir s) - 1 -- TODO: one failure
          then case v of
            Just v' -> lift $ putStrLn $ show (ident s) ++ " accepted " ++ show v'
            Nothing -> return ()
        else return ()
      _ -> return ()

{- proposer' = do
  s <- get
  if leader 
    then $ do
       modify s ballotNum + 1
       broadcast ballotNum + 1
       receive Ack from Majority
       if map (== _|_) then myVal = initV
       else myVal = recvVal max ballot
       broadcast "accept" bn myVAl
       broadcast "decide" v
    else $ return () -} 
