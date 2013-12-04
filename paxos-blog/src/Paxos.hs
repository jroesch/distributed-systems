{-# LANGUAGE TemplateHaskell #-}
module Paxos where

import Control.Monad.State
import Control.Concurrent
import Control.Lens
import Data.Maybe
import qualified Data.Map as M
import Data.List
import Data.Functor

import Paxos.Message
import qualified Paxos.Directory.Remote as D

data ProcessState = ProcessState {
    _ident   :: Int
  , _inst    :: Int
  , _decided :: Value
  , _dir     :: D.Directory
  , _pState  :: ProposerState
  , _aState  :: AcceptorState
  }

data ProposerState = ProposerState {
    _pBallotNum :: MVar Ballot
  , _pAcceptNum :: Ballot
  , _pAcceptVal :: Value
  , _ackM       :: MVar ([InstanceMessage], Int) -- clean this up
  , _acceptedM  :: MVar Int -- clean this up
  }

data AcceptorState = AcceptorState {
    _aBallotNum :: Ballot
  , _aAcceptNum :: Ballot
  , _aAcceptVal :: Value
  , _instVar    :: MVar Int
  }

makeLenses ''ProposerState
makeLenses ''AcceptorState
makeLenses ''ProcessState

type PaxosInstance a = StateT ProcessState IO a

initialState :: D.Directory -> D.Pid -> Int -> MVar Int -> IO ProcessState
initialState d pid inst instVar = do
  v <- newMVar bNum
  ackM <- newMVar ([], 0)
  acceptedM <- newMVar 0
  return ProcessState {
    _ident   = pid,
    _inst    = inst,
    _decided = Nothing,
    _dir     = d,
    _pState  = ProposerState {
      _pBallotNum = v,
      _pAcceptNum = aNum,
      _pAcceptVal = aVal,
      _ackM       = ackM,
      _acceptedM  = acceptedM
    },
    _aState = AcceptorState {
      _aBallotNum = bNum,
      _aAcceptNum = aNum,
      _aAcceptVal = aVal,
      _instVar    = instVar
    }
  }
  where
    bNum = Ballot (0, pid)
    aNum = Ballot (0, 0)
    aVal = Nothing

broadcastP :: InstanceMessage -> PaxosInstance ()
broadcastP m = do
  d <- use dir
  i <- use inst
  lift $ D.broadcast d (Message i m)

sendP :: D.Pid -> InstanceMessage -> PaxosInstance ()
sendP p m = do
  d <- use dir
  i <- use inst
  lift $ D.send (d) p (Message i m)

propose :: PaxosInstance ()
propose = do
  i <- use ident
  s <- use pState
  Ballot (prev, _) <- lift $ takeMVar $ s^.pBallotNum
  let new = Ballot (prev + 1, i)
  -- reset acks and accepted
  lift $ modifyMVar_ (s^.ackM) $ \_ -> return ([], 0)
  lift $ modifyMVar_ (s^.acceptedM) $ \_ -> return 0
  broadcastP $ Prepare new
  lift $ putMVar (s^.pBallotNum) new

maxAck :: [InstanceMessage] -> Value -- bad assumptions here, that all message will match this pattern
maxAck acks = let Ack a b v = maximumBy (\(Ack _ a _ ) (Ack _ b _) -> compare a b) acks in v

acceptor :: InstanceMessage -> PaxosInstance Value 
acceptor msg = do
    s <- use aState
    d <- use decided
    case d of
      Just v -> case msg of
        Decide _ -> return Nothing
        _ -> do
          broadcastP $ Decide v
          return Nothing
      Nothing -> do
        case msg of
          Prepare bn | bn >= (view aBallotNum s) -> do
            -- update the current highest instance
            inst <- use inst
            lift $ modifyMVar_ (s ^. instVar) $ \i -> return $ max i (inst +1)
            aState . aBallotNum .= bn
            broadcastP $ Ack bn (view aAcceptNum s) (view aAcceptVal s)
            return Nothing
          Accept b v | b >= view aBallotNum s -> do -- Fix maybe code here
            -- ensure we dont send accept message multiple times
            if (view aAcceptNum s) /= b then do
              aState . aAcceptNum .= b
              aState . aAcceptVal .= Just v
              broadcastP $ Accept b v
              return Nothing
            else return Nothing
          Decide v -> do
            decided .= Just v
            return $ Just v
          _ -> return Nothing

proposer :: String -> InstanceMessage -> PaxosInstance (Maybe Bool)
proposer value msg = do
    s <- use pState
    let var = s^.pBallotNum
    ballotNum <- lift $ takeMVar var
    a <- case msg of
      Ack bn b v | bn == ballotNum -> do
        (oldL, oldC) <- lift $ takeMVar $ s^.ackM
        let newL = msg : oldL
        let newC = oldC + 1
        d <- use dir
        size <- lift $ D.size d
        if newC > div size 2 && s^.pAcceptNum /= bn
          then do
            let new = if all (\(Ack bal b v) -> isNothing v) newL 
                        then value
                        else fromJust $ maxAck newL
            pState . pAcceptVal .= Just new
            pState . pAcceptNum .= bn
            lift $ putMVar (s^.ackM) (newL, newC)
            broadcastP $ Accept ballotNum new
            return Nothing
          else do
            lift $ putMVar (s^.ackM) (newL, newC)
            return Nothing
      Accept b v | b == ballotNum -> do
        new <- lift $ modifyMVar (s^.acceptedM) $ \old -> return (old + 1, old + 1)
        size <- use dir >>= lift . D.size
        if new == size - 2 -- TODO: one failure
        then do
          broadcastP $ Decide v
          return $ Just True
        else return Nothing
      Decide _ -> return $ Just False
      _ -> return Nothing
    lift $ putMVar var ballotNum
    return a
