{-# LANGUAGE TemplateHaskell #-}
module Paxos where

import Control.Monad.State
import Control.Lens
import Data.Maybe
import qualified Data.Map as M
import Data.List
import Data.Functor

import Paxos.Message
import qualified Paxos.Directory as D

data ProcessState = ProcessState {
    _ident  :: Int
  , _dir    :: D.Directory
  , _pState :: ProposerState
  , _aState :: AcceptorState
  } deriving (Show)

data ProposerState = ProposerState {
    _pBallotNum :: Ballot
  , _pAcceptNum :: Ballot
  , _pAcceptVal :: Value
  , _ackM      :: ([Message], Int) -- clean this up
  , _acceptedM :: Int -- clean this up
  } deriving (Show)

data AcceptorState = AcceptorState {
    _aBallotNum :: Ballot
  , _aAcceptNum :: Ballot
  , _aAcceptVal :: Value
  } deriving (Show)

makeLenses ''ProposerState
makeLenses ''AcceptorState
makeLenses ''ProcessState

type PaxosInstance a = StateT ProcessState IO a

initialState :: D.Directory -> D.Pid -> ProcessState
initialState d pid = 
  ProcessState {
    _ident = pid,
    _dir = d,
    _pState = ProposerState {
      _pBallotNum = bNum,
      _pAcceptNum = aNum,
      _pAcceptVal = aVal,
      _ackM       = ([], 0),
      _acceptedM  = 0
    },
    _aState = AcceptorState {
      _aBallotNum = bNum,
      _aAcceptNum = aNum,
      _aAcceptVal = aVal
    }
  }
  where
    bNum = Ballot (0, pid)
    aNum = Ballot (0, 0)
    aVal = Nothing

broadcastP :: Message -> PaxosInstance ()
broadcastP m = do
  d <- use dir
  lift $ D.broadcast d m

sendP :: D.Pid -> Message -> PaxosInstance ()
sendP p m = do
  d <- use dir
  lift $ D.send (d) p m

propose :: PaxosInstance ()
propose = do
  i <- use ident
  if i == 1 then do
    Ballot (prev, _) <- use $ pState . pBallotNum
    let new = Ballot (prev + 1, i)
    pState . pBallotNum .= new
    broadcastP $ Prepare new
  else
    return ()

maxAck :: [Message] -> Value -- bad assumptions here, that all message will match this pattern
maxAck acks = let Ack a b v = maximumBy (\(Ack _ a _ ) (Ack _ b _) -> compare a b) acks in v

acceptor :: Message -> PaxosInstance ()
acceptor msg = do
    s <- use aState
    case msg of
      Prepare bn | bn >= (view aBallotNum s) -> do
        aState . aBallotNum .= bn
        broadcastP $ Ack bn (view aAcceptNum s) (view aAcceptVal s)
      Accept b v | b >= view aBallotNum s -> do -- Fix maybe code here
        -- ensure we dont send accept message multiple times
        if (view aAcceptNum s) /= b then do
          aState . aAcceptNum .= b
          aState . aAcceptVal .= v
          broadcastP $ Accept b v
        else return ()
      Decide v -> return () -- placeholder
      otherwise -> return ()

proposer :: String -> Message -> PaxosInstance ()
proposer value msg = do
    s <- use pState
    case msg of
      Ack bn b v | bn == s^.pBallotNum -> do
        let (oldL, oldC) = s^.ackM
        let newL = msg : oldL
        let newC = oldC + 1
        d <- use dir
        if newC > div (M.size d) 2 && s^.pAcceptNum /= bn
          then do
            let new = if all (\(Ack bal b v) -> isNothing v) newL 
                        then Just value
                        else maxAck newL
            pState . pAcceptVal .= new
            pState . pAcceptNum .= bn
            broadcastP $ Accept (s^.pBallotNum) new
          else pState . ackM .= (newL, newC) -- clean up acceptM
      Accept b v -> do
        let new = s^.acceptedM + 1
        pState . acceptedM .= new
        d <- use dir
        if new == M.size d - 1 -- TODO: one failure
          then case v of
            Just v' -> lift $ putStrLn $ "Accepted " ++ show v'
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
