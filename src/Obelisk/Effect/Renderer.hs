{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE ConstraintKinds #-}
module Obelisk.Effect.Renderer where

import Control.Monad.Reader
import qualified SDL
import qualified SDL.Primitive as SDL
import Control.Lens
import Linear
import Foreign.C.Types
import Data.Bool
import qualified Data.Set as S

import Obelisk.Config
import Obelisk.State
import Obelisk.Effect.Debug
import Obelisk.Math.Vector
import Obelisk.Math.Homogenous
import Obelisk.Wrapper.SDLRenderer
import Obelisk.Engine.DDA
import Obelisk.Engine.Raycast

--COLORS
white :: SDL.Color
white = SDL.V4 maxBound maxBound maxBound maxBound
red :: SDL.Color
red = SDL.V4 maxBound 0 0 maxBound
blue :: SDL.Color
blue = SDL.V4 0 0 maxBound maxBound
black :: SDL.Color
black = SDL.V4 0 0 0 0
yellow :: SDL.Color
yellow = SDL.V4 255 255 0 maxBound

--GodBolt Colors
backgroundColor :: SDL.Color
backgroundColor = SDL.V4 34 34 34 maxBound
gridColor :: SDL.Color
gridColor = SDL.V4 63 63 63 maxBound
filledTileColor :: SDL.Color
filledTileColor = SDL.V4 51 51 102 maxBound
doorTileColor :: SDL.Color
doorTileColor = SDL.V4 102 51 102 maxBound
arrowColor :: SDL.Color
arrowColor = SDL.V4 255 51 51 maxBound

wallTypeToColor :: WallType -> SDL.Color
wallTypeToColor FW = filledTileColor
wallTypeToColor EW = backgroundColor
wallTypeToColor DW = doorTileColor

class Monad m => Renderer m where
    clearScreen :: m ()
    drawScreen :: m ()
    fillBackground :: m ()
    drawDebug :: Vars -> m ()

type SDLCanDraw m = (SDLRenderer m, MonadReader Config m)

clearScreen' :: SDLCanDraw m => m ()
clearScreen' = do
    renderer <- asks cRenderer
    clearRenderer renderer

drawScreen' :: SDLCanDraw m => m ()
drawScreen' = do
    window <- asks cWindow 
    updateWindowSurface window

fillBackground' :: SDLCanDraw m => m ()
fillBackground' = do
    surface <- asks cSurface
    surfaceFillScreenRect surface backgroundColor

type GridTransform = M22Affine Double

drawDebug' :: (Debug m , SDLCanDraw m) => Vars -> m ()
drawDebug' gs = do
    let ws = worldSize . world $ gs
    screenWidth <- asks cScreenWidth
    screenHeight <- asks cScreenHeight

    let zoomLimiter = 0.95
    let zoomFactor = fromIntegral screenHeight / fromIntegral ws * zoomLimiter

    --TODO rotation focus mechanism
    let rotationFactor = bool 0.0 (vectorAngle. direction $ player gs) $ rotateToPView gs
    let focus = bool Nothing (Just (position . player $ gs)) $ rotateToPView gs

    let tPDCenter = translateToPDCenter screenWidth screenHeight
    let gtp = gridT ws zoomFactor rotationFactor focus tPDCenter
    --dprint gtp

    let visitedSet = S.unions $ visitedPositions gs <$> genRays rayCount (player gs)

    drawGridTiles (world gs) visitedSet gtp
    drawGrid ws gtp
    drawPlayer (player gs) gtp
    
    -- drawRaycastIntersectionSimple (player gs) gtp
    drawRaycastIntersections (player gs) gtp
    --TODO draw sideRaycastIntersections

---------------------------------------------------------------
rayCount = 1 --TODO FIXME

drawGrid :: SDLCanDraw m => CInt -> GridTransform -> m ()
drawGrid ws t = do
    screenRenderer <- asks cRenderer

    let hlines = appDTFloor t (horizontal_lines ws) :: [Line]
    let vlines = appDTFloor t (vertical_lines ws) :: [Line]

    forM_ hlines drawGridLine
    forM_ vlines drawGridLine 
    where
        vertical_lines ws = [(homoCoords (V2 x 0), homoCoords (V2 x ws)) | x <- [0..ws]]
        horizontal_lines ws = [(homoCoords (V2 0 y), homoCoords (V2 ws y)) | y <- [0..ws]]

drawGridLine :: (SDLCanDraw m) => Line -> m ()
drawGridLine (start, end) = do
    screenRenderer <- asks cRenderer
    drawLine screenRenderer (dropHomoCoords start) (dropHomoCoords end) gridColor

drawGridTiles :: (SDLCanDraw m) => WorldTiles -> S.Set (V2 Int) -> GridTransform -> m ()
drawGridTiles world visitedSet t = do
    let ws = worldSize world
    screenRenderer <- asks cRenderer 

    let projectVertToPD = dropHomoCoords . fmap floor . (t !*) . homoCoords . fmap fromIntegral
    let inds = [(x,y) | x <- [0..ws -1], y <- [0..ws - 1]]
    let quads = [blastFmap4Tupple projectVertToPD (V2 x y, V2 (x+1) y, V2 x (y+1), V2 (x+1) (y+1)) | x <- [0..ws - 1], y <- [0..ws - 1]] :: [(SDL.Pos,SDL.Pos,SDL.Pos,SDL.Pos)]

    forM_ (zip inds quads) (\((x,y),(vA,vB,vC,vD)) -> do
        let sampleColor = wallTypeToColor $ accessMap world (fromIntegral y) (fromIntegral x)
        let tileColor = if S.member (V2 (fromIntegral x) (fromIntegral y)) visitedSet
                        --Lighten the tiles that get rayCasted
                        then sampleColor + V4 20 20 20 0
                        else sampleColor 

        fillTriangle screenRenderer vA vB vC tileColor
        fillTriangle screenRenderer vB vC vD tileColor
        )

drawRaycastIntersectionSimple :: (SDLCanDraw m) => PVars -> GridTransform -> m ()
drawRaycastIntersectionSimple player t = do
    let intersections = take 10 $ shootRay player (position player + direction player)
    let intersectionPosXs = fmap (pointToScreenSpace t) $ intersectionPositions $ fmap fst intersections

    screenRenderer <- asks cRenderer
    forM_ intersectionPosXs (\pos -> do
            circle screenRenderer pos 3 yellow
        )

drawRaycastIntersections :: (SDLCanDraw m) => PVars -> GridTransform -> m ()
drawRaycastIntersections player t = do
    -- let rayCount = 5 --TODO REMOVEME
    let intersectionLimit = 10 --TODO REMOVEME
    let rayPathIntersections = fmap ((fmap (pointToScreenSpace t). intersectionPositions . fmap fst) . take intersectionLimit) (genRays rayCount player)

    screenRenderer <- asks cRenderer
    forM_ rayPathIntersections (\intersections -> do
        forM_ intersections (\pos -> do
            circle screenRenderer pos 3 yellow))

drawPlayer :: (SDLCanDraw m) => PVars -> GridTransform -> m ()
drawPlayer player gtp = do
    drawPlayerCircle player gtp
    drawCameraPlane player gtp
    drawPlayerArrow player gtp

drawPlayerArrow :: (SDLCanDraw m) => PVars -> GridTransform -> m ()
drawPlayerArrow player gtp = do
    screenRenderer <- asks cRenderer
    let playerT = translate (position player^._x) (position player^._y)
    let arrowT = gtp !*! playerT !*! rotation (vectorAngle . direction $ player)
                                                --                 |
    --TODO figure out a better way to handle the scaling done here V
    let dir_len = norm $ direction player
    let arrow_line = (homoCoords $ V2 0.0 0.0 , homoCoords $ V2 10.0 0.0)
    let (arrow_p0, arrow_p1) = blastFmapPair (apDT arrowT) arrow_line

    --Draw the line body of the arrow
    drawLine screenRenderer arrow_p0 arrow_p1 red

    --Draw Arrow
    --TODO assert direction is larger than the arrow length so we dont get a graphical error
    let arrowLength = 0.25
    let arrowWidth = 0.06
    let baseArrow = (homoCoords $ V2 0.0 (-arrowWidth), homoCoords $ V2 arrowLength 0.0, homoCoords $ V2 0.0 arrowWidth) :: (HV2 Double, HV2 Double, HV2 Double)

    let (arrowVA, arrowVB, arrowVC) = blastFmap3Tupple (apDT (arrowT !*! translate (1.05*dir_len - arrowLength) 0.0)) baseArrow
    fillTriangle screenRenderer arrowVA arrowVB arrowVC arrowColor

drawCameraPlane :: (SDLCanDraw m) => PVars -> GridTransform -> m ()
drawCameraPlane player gtp = do
    screenRenderer <- asks cRenderer
    let ppos = position player
    let camTail = pointToScreenSpace gtp $ ppos + direction player - camera_plane player
    let camHead = pointToScreenSpace gtp $ ppos + direction player + camera_plane player
    drawLine screenRenderer camTail camHead white

    let edgeLength = 10.0
    let leftEnd = pointToScreenSpace gtp $ ppos + (edgeLength *^ (direction player - camera_plane player))
    drawLine screenRenderer (pointToScreenSpace gtp ppos) leftEnd gridColor

    let rightEnd = pointToScreenSpace gtp $ ppos + (edgeLength *^ (direction player + camera_plane player))
    drawLine screenRenderer (pointToScreenSpace gtp ppos) rightEnd gridColor

drawPlayerCircle :: (SDLCanDraw m) => PVars -> GridTransform -> m ()
drawPlayerCircle player gtp = do
    screenRenderer <- asks cRenderer
    let px = position player ^._x
    let py = position player ^._y
    let t = gtp !*! translate px py
    let circle_pos = dropHomoCoords . fmap floor . (t !*) . homoCoords $ V2 0.0 0.0
    let circle_radius = 3
    fillCircle screenRenderer circle_pos circle_radius white

------------------------------------------------------------------

translateToPDCenter :: CInt -> CInt -> M22Affine Double
translateToPDCenter screenWidth screenHeight = translate (fromIntegral screenWidth / 2.0) (fromIntegral screenHeight / 2.0)

gridT :: CInt -> Double -> Double -> Maybe (V2 Double) -> M22Affine Double -> GridTransform
gridT worldSize zoomFactor rotationFactor Nothing translateToPDCenter = translateToPDCenter !*! rotationT !*! zoomT zoomFactor !*! centerToLocalOrigin
    where
        delta = fromIntegral worldSize / 2
        centerToLocalOrigin = translate (-delta) (-delta) :: M22Affine Double
        rotationT = rotation rotationFactor

gridT worldSize zoomFactor rotationFactor (Just focus) translateToPDCenter = translateToPDCenter !*! zt !*! rotationT !*! playerToLocalOrigin
    where
        zt = zoomT zoomFactor
        wsMid = fromIntegral worldSize / 2.0
        playerToLocalOrigin = translate (-focus ^._x) (-focus ^._y)  :: M22Affine Double
        rotationT = rotation ((-pi/2.0) - rotationFactor)

blastFmapPair :: (t -> b) -> (t, t) -> (b, b)
blastFmapPair f (a,b) = (f a, f b)
blastFmap3Tupple :: (t -> c) -> (t, t, t) -> (c, c, c)
blastFmap3Tupple f (a,b,c) = (f a, f b, f c)
blastFmap4Tupple :: (t -> d) -> (t, t, t, t) -> (d, d, d, d)
blastFmap4Tupple f (a,b,c,d) = (f a, f b, f c, f d)

pointToScreenSpace :: GridTransform -> V2 Double -> V2 CInt
pointToScreenSpace t = dropHomoCoords . fmap floor . (t !*) . homoCoords

pdToWorldT :: M22Affine Double -> M22Affine Double
pdToWorldT gridTransform = inv33 gridTransform


tgridT = V3 (V3 45.599999999999994 0.0 92.00000000000003) (V3 0.0 45.599999999999994 12.000000000000028) (V3 0.0 0.0 1.0)
tz = pdToWorldT tgridT
tresult x y = dropHomoCoords . (fmap floor) . (tz !*) . homoCoords $ V2 x y --TODO we need to figure out mouse position on screen and pipe it into this

pdToWorldPos t x y = dropHomoCoords . ((pdToWorldT t) !*) . homoCoords $ V2 x y
pdToGridPos t x y = dropHomoCoords . (fmap floor) . ((pdToWorldT t) !*) . homoCoords $ V2 x y