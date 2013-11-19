{-# LANGUAGE FlexibleInstances, TemplateHaskell, OverloadedStrings, GADTs #-}
module Main where

import Test.Framework
import Test.Framework.TH
import Test.Framework.Providers.HUnit
import Test.HUnit.Base
import Control.Concurrent (forkIO, forkFinally, killThread)
import Data.IORef
import System.IO
import Control.Concurrent.MVar
import Paxos.Remote.Channel

main = defaultMain [testGroup "Group1" [
                    testCase "single remote channel" test_singleRemoteChannel, 
                    testCase "read and write are identity" test_hRead_hWrite_Id
                    ]]

test_hRead_hWrite_Id = do
  (_, handle) <- openTempFile "/tmp" "fobar"
  hSetBinaryMode handle True
  hWrite handle ("foo" :: String)
  hSeek handle AbsoluteSeek 0
  str <- hRead handle :: IO String
  "foo" @=? str

test_singleRemoteChannel = do
    mreg <- channelRegistry :: IO (ChannelRegistry String)
    tid <- forkIO $ startChannelService mreg
    wChan <- (newChan "localhost" 9000) :: IO (Chan String WriteMode)
    rChan <- openReadChan mreg 0
    writeChan wChan "foo"
    msg <- readChan rChan
    killThread tid
    msg @=? "foo"

