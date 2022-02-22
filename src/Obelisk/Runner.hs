{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE MultiWayIf #-}
module Obelisk.Runner where

import Control.Monad.Reader
import Control.Monad.State
import Linear
import Control.Lens
import qualified SDL
import Data.ListZipper
import Data.Foldable ( forM_ )
import Control.Monad (when)

import Obelisk.Config
import Obelisk.State
import Obelisk.Effect.Renderer
import Obelisk.Effect.Debug
import Obelisk.Wrapper.SDLInput
import Obelisk.Engine.Input
import Obelisk.Manager.Input
import Obelisk.Math.Homogenous
import Obelisk.Graphics.Primitives
import Obelisk.Graphics.UIScene
import Data.Text (center)

presentationRenderLoop :: ( MonadReader Config m
            , MonadState Vars m
            , SDLInput m
            , HasInput m
            , Debug m
            , Renderer m ) => Presentation -> m ()
presentationRenderLoop presentation = do
    --Make a zipper and launch if the zipper isn't nothing
        forM_ (zipper presentation) sceneRenderLoop'

sceneRenderLoop' :: ( MonadReader Config m
            , MonadState Vars m
            , SDLInput m
            , HasInput m
            , Debug m
            , Renderer m ) => ListZipper UIScene -> m ()
sceneRenderLoop' sceneZipper = do

    updateInput
    clearScreen
    fillBackground

    input <- getInput
    let quitSignal = iQuit input
    let sceneChangeSignal = presentationInput input

    let sceneZipper' = case sceneChangeSignal of
                        Nothing -> sceneZipper
                        Just lzOp -> execListZipperOpOr lzOp sceneZipper

    let currentScene = sceneZipper' ^. focus
    -- dprint currentScene

    sequence_ $ drawGraphicDebug <$> graphic_elems currentScene
    drawScreen

    --TODO modify sceneZipper based on input

    unless quitSignal (sceneRenderLoop' sceneZipper')

--Handles switching the scene for our the presentation
presentationInput :: Input -> Maybe (ListZipperOp' UIScene)
presentationInput (Input True False _ _) = Just moveLeft
presentationInput (Input False True _ _) = Just moveRight
presentationInput _ = Nothing


grenderLoop :: ( MonadReader Config m
            , MonadState Vars m
            , SDLInput m
            , HasInput m
            , Debug m
            , Renderer m ) => Graphic (Shape Float) -> m ()
grenderLoop g = do
    updateInput
    clearScreen
    fillBackground

    input <- getInput
    let quitSignal = iQuit input

    drawGraphicDebug g
    drawScreen
    fillBackground

    unless quitSignal (grenderLoop g)

gRenderMouseLookLoop :: ( MonadReader Config m
            , MonadState Vars m
            , SDLInput m
            , HasInput m
            , Debug m
            , Renderer m ) => (V2 Float ->m (Graphic (Shape Float))) -> m ()
gRenderMouseLookLoop g = do
    updateInput
    clearScreen
    fillBackground

    input <- getInput
    let quitSignal = iQuit input

    absMouseLoc <- getMouseAbsoluteLoc
    --Implicitly assumes world is size 10 for diagram.
    --TODO fix this math
    screenWidth <- asks cScreenWidth
    screenHeight <- asks cScreenHeight

    --TODO mousescroll zooming
    --TODO translate with mouse
    let mouseTx = 200.0
    let mouseTy = 100.0
    let zoomAmmount = 1.0

    --Transforms
    let screenOnWorldGrid = rawCenterScreenOnWorldGrid 10 screenWidth screenHeight --todo
    let translateMouse = translate mouseTx mouseTy
    let zoomMouse = zoomT zoomAmmount 
    let gtp =  zoomMouse !*! translateMouse !*! screenOnWorldGrid 

    let worldLoc = rawPDtoWorldPos gtp (fromIntegral <$> absMouseLoc)

    -- dprint "---"
    -- dprint absMouseLoc
    -- dprint worldLoc
    -- dprint "---"

    --TODO dump state

    graphic <- g worldLoc
    drawGraphicDebugWithMatrix graphic gtp

    drawScreen
    fillBackground

    unless quitSignal (gRenderMouseLookLoop g)



mainLoop :: ( MonadReader Config m
            , MonadState Vars m
            , SDLInput m
            , HasInput m
            , Debug m
            , Renderer m ) => m ()
mainLoop = do
    updateInput
    clearScreen
    fillBackground

    -- quitSignal <- checkQuitSignal
    --TODO process input update to rotation
    input <- getInput
    old_gs <- get
    let dir = direction $ player old_gs :: V2 Float
    let cplane = camera_plane $ player old_gs

    let rotationT = rotation2 0.05
    let quitSignal = iQuit input
    let (rotated_dir, rotated_cplane) = if | iLeft input && not (iRight input) -> (dir *! rotation2 0.05, cplane *! rotation2 0.05)
                                           | iRight input && not (iLeft input) -> (dir *! rotation2 (-0.05), cplane *! rotation2 (-0.05))
                                           | otherwise -> (dir, cplane)


    modify $ pVars %~ (\v -> v { direction = rotated_dir, camera_plane = rotated_cplane})

    time <- getTime
    let elapsed_seconds = fromIntegral (toInteger time) / 1000.0
    let rotationFactor = elapsed_seconds --0.0

    --gameTick hs TODO updateStep


    --TODO once we finish debug stuff and get drawing done
        --Implement press tab to show debug screen

    gs <- get

    when (iPrintState input) $ printGS gs

    drawDebug gs
    drawScreen

    fillBackground

    unless quitSignal mainLoop