module Obelisk.Graphics.DebugUI where

import Foreign.C.Types (CInt)
import Linear
import Control.Lens
import qualified SDL
import qualified SDL.Primitive as SDL
import qualified Data.Set as S
import Control.Monad.Reader 

import Obelisk.State

import Obelisk.Math.Vector
import Obelisk.Math.Homogenous ( rotation, translate )
import Obelisk.Graphics.Primitives

-- UI CONSTANTS
gridColor :: SDL.Color
gridColor = SDL.V4 63 63 63 maxBound
white :: SDL.Color
white = SDL.V4 maxBound maxBound maxBound maxBound
red :: SDL.Color
red = SDL.V4 maxBound 0 0 maxBound
arrowColor :: SDL.Color
arrowColor = SDL.V4 255 51 51 maxBound

--GodBolt Colors
backgroundColor :: SDL.Color
backgroundColor = SDL.V4 34 34 34 maxBound
filledTileColor :: SDL.Color
filledTileColor = SDL.V4 51 51 102 maxBound
doorTileColor :: SDL.Color
doorTileColor = SDL.V4 102 51 102 maxBound

wallTypeToColor :: WallType -> SDL.Color
wallTypeToColor FW = filledTileColor
wallTypeToColor EW = backgroundColor
wallTypeToColor DW = doorTileColor

-- One thing to note about this is that all of this should be done in world coordinates
-- The Grid to player as center local -> screen AFT will be applied as an AffineT in the renderer

worldGridGraphic :: CInt -> Graphic (Shape Double)
worldGridGraphic ws = GroupPrim gridLines
    where
        worldSize = fromIntegral ws
        verticalLines ws   = [Prim (Line (V2 x 0) (V2 x ws) gridColor) | x <- [0..ws]]
        horizontalLines ws = [Prim (Line (V2 0 y) (V2 ws y) gridColor) | y <- [0..ws]]
        gridLines = verticalLines worldSize ++ horizontalLines worldSize

worldGridTilesGraphic :: WorldTiles -> S.Set (V2 Int) -> Graphic (Shape Double)
worldGridTilesGraphic world visitedSet = do
    let ws = worldSize world 
    
    let inds = [(x,y) | x <- [0..ws -1], y <- [0..ws - 1]]
    let quads = [(V2 x y, V2 (x+1) y, V2 x (y+1), V2 (x+1) (y+1)) | x <- [0.. fromIntegral ws - 1], y <- [0.. fromIntegral ws - 1]]

    let prims = zip inds quads <&> (\((x,y), (vA,vB,vC,vD)) -> do
            let sampleColor = wallTypeToColor $ accessMap world (fromIntegral x) (fromIntegral y)
            let tileColor = if S.member (V2 (fromIntegral x) (fromIntegral y)) visitedSet
                --Lighten the tiles that get rayCasted
                --TODO this should be a graphic highlight
                then sampleColor + V4 20 20 20 0
                else sampleColor

            [Prim $ FillTriangle vA vB vC tileColor,
             Prim $ FillTriangle vB vC vD tileColor])
    GroupPrim $ concat prims

playerGraphic :: PVars -> Graphic (Shape Double)
playerGraphic p = GroupPrim [
                    playerCircleGraphic p,
                    cameraPlaneGraphic p,
                    playerArrowGraphic p
                ]

playerArrowGraphic :: PVars -> Graphic (Shape Double)
playerArrowGraphic player = do
    let playerT = translate (position player^._x) (position player^._y)
    let arrowT = playerT !*! rotation (vectorAngle . direction $ player)
                                                --                 |
    --TODO figure out a better way to handle the scaling done here V
    let dir_len = norm $ direction player
    let arrowLine = Prim $ Line (V2 0 0) (V2 10 0) red

    --Draw Arrow
    --TODO assert direction is larger than the arrow length so we dont get a graphical error
    let arrowLength = 0.25
    let arrowWidth = 0.06

    let arrowHead = Prim (FillTriangle
                            (V2 0.0 (-arrowWidth))
                            (V2 arrowLength 0.0)
                            (V2 0.0 arrowWidth)
                            arrowColor)

    let arrowHeadDisplacementT = translate (1.05*dir_len - arrowLength) 0.0

    let arrow = AffineT arrowT $ GroupPrim [
                             arrowLine,
                             AffineT arrowHeadDisplacementT arrowHead
                          ]

    arrow

cameraPlaneGraphic :: PVars -> Graphic (Shape Double)
cameraPlaneGraphic p = do
    let ppos = position p
    let camTail = ppos + direction p - camera_plane p
    let camHead = ppos + direction p + camera_plane p

    let planeLine = Line camTail camHead white

    let edgeLength = 10.0
    let leftEnd = ppos + (edgeLength *^ (direction p - camera_plane p))
    let leftCamEdgeLine = Line ppos leftEnd gridColor

    let rightEnd = ppos + (edgeLength *^ (direction p + camera_plane p))
    let rightCamEdgeLine = Line ppos rightEnd gridColor

    GroupPrim [
        Prim planeLine,
        Prim leftCamEdgeLine,
        Prim rightCamEdgeLine]

playerCircleGraphic :: PVars -> Graphic (Shape Double)
playerCircleGraphic p = do
    let px = position p ^._x
    let py = position p ^._y
    let circle_radius = 3
    AffineT (translate px py) $ Prim (Circle (V2 0.0 0.0) circle_radius white)

