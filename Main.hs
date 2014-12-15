{-# LANGUAGE TemplateHaskell, DeriveGeneric, DeriveDataTypeable #-}

import Control.Distributed.Process
import Control.Distributed.Process.Backend.SimpleLocalnet
import Control.Distributed.Process.Closure
import Control.Distributed.Process.Node
import Control.Monad (forever, forM_)
import System.Environment (getArgs)
import Repos hiding (main)

slave :: (ProcessId, ProcessId) -> Process ()
slave (master, workQueue) = do us <- getSelfPid
                               go us
  where go us = do send workQueue us
                   receiveWait
                     [ match $ \nm -> liftIO(fetchGHProfile nm) >>= send master >> go us
                     , match $ \() -> return ()
                     ]

remotable ['slave]

accProfiles :: Int -> Process [Either String GHProfile]
accProfiles = go []
  where
    go :: [Either String GHProfile] -> Int -> Process [Either String GHProfile]
    go acc 0 = return $ reverse acc
    go acc n = do m <- expect
                  go (m:acc) (n-1)

master :: [String] -> [NodeId] -> Process [Either String GHProfile]
master usernames slaves = do
  us <- getSelfPid
  workQueue <- spawnLocal $ do
    forM_ usernames $ \u -> expect >>= flip send u
    forever $ expect >>= flip send ()

  forM_ slaves $ \nid -> spawn nid ($(mkClosure 'slave) (us, workQueue))
  accProfiles $ length usernames

rtable :: RemoteTable
rtable = __remoteTable initRemoteTable

main :: IO ()
main = do
  args <- getArgs
  case args of
    "master":host:port:usernames -> do
      backend <- initializeBackend host port rtable
      startMaster backend $ \slaves -> do
        result <- master usernames slaves
        liftIO $ print result

    ["slave", host, port] -> do
      backend <- initializeBackend host port rtable
      startSlave backend

    _ -> putStrLn "Bad args"
