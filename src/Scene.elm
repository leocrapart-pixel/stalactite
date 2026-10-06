module Scene exposing (Options, draw)

{-| Draws the cave chamber.

Physical space is metres; this module maps it to canvas pixels. The chamber has
a fixed vertical extent, so the stalactite is seen to elongate against an
unchanging room rather than being rescaled on every frame. The chamber is
deeper than it is wide, which is how a cave passage actually looks.

-}

import Array
import Canvas as C
import Physics as P exposing (Env, Sim)
import Ui


{-| Everything the renderer needs.
-}
type alias Options =
    { width : Float
    , height : Float
    , env : Env
    , sim : Sim
    , time : Float

    -- ^ seconds of wall-clock time, drives the drip animation
    , chamberM : Float

    -- ^ height of the modelled chamber, metres
    , showRings : Bool
    , stalagmiteM : Float

    -- ^ height of the floor boss below the drip, metres (0 = none)
    }


type alias Layout =
    { cx : Float
    , ceilY : Float
    , floorY : Float
    , scale : Float
    }


layout : Options -> Layout
layout opts =
    let
        padTop =
            52.0

        padBottom =
            62.0

        usable =
            max 120.0 (opts.height - padTop - padBottom)
    in
    { cx = opts.width / 2.0
    , ceilY = padTop
    , floorY = padTop + usable
    , scale = usable / max opts.chamberM 0.05
    }


toY : Layout -> Float -> Float
toY l depth =
    l.ceilY + depth * l.scale


{-| Physical profile as a list of (depth below ceiling, radius).
-}
profilePoints : Sim -> List ( Float, Float )
profilePoints sim =
    P.view P.defaultEnv sim |> .points


{-| Build the whole canvas scene as a value.
-}
draw : Options -> C.Draw
draw opts =
    let
        l =
            layout opts

        pts =
            profilePoints opts.sim

        body =
            List.map (\( d, r ) -> ( l.cx + r * l.scale, toY l d )) pts
                ++ List.map (\( d, r ) -> ( l.cx - r * l.scale, toY l d )) (List.reverse pts)

        apex =
            List.head pts |> Maybe.withDefault ( 0.0, P.seedRadius )
    in
    { width = opts.width
    , height = opts.height
    , background = "#070a0e"
    , shapes =
        [ C.rect 0
            0
            opts.width
            opts.height
            (C.linear
                [ ( 0.0, "#0e141c" ), ( 0.5, "#0a0e14" ), ( 1.0, "#06080b" ) ]
                0
                0
                0
                opts.height
            )
        , chamberGlow opts l
        , rockCeiling opts l
        , depthGrid opts l
        , C.polygon body
            (C.linear
                [ ( 0.0, "#dcc7a0" )
                , ( 0.2, "#c4ad86" )
                , ( 0.65, "#9e8867" )
                , ( 1.0, "#79664c" )
                ]
                (l.cx - 60)
                (toY l 0.0)
                (l.cx + 60)
                (toY l opts.chamberM)
            )
        , litFace pts l
        , if opts.showRings then
            growthRings opts l pts

          else
            C.Groups []
        , waterFilm pts l
        , C.polyline (capArc opts l apex) (C.stroke "rgba(255,248,232,0.30)" 1.3)
        , C.Groups (fallingDrops opts l apex)
        , stalagmite opts l
        , C.Groups (axisLegend opts l)
        ]
    }


chamberGlow : Options -> Layout -> C.Shape
chamberGlow opts l =
    C.rect 0
        0
        opts.width
        opts.height
        (C.radial
            [ ( 0.0, "rgba(126,158,196,0.11)" )
            , ( 0.6, "rgba(90,120,150,0.03)" )
            , ( 1.0, "rgba(0,0,0,0)" )
            ]
            l.cx
            (l.ceilY + (l.floorY - l.ceilY) * 0.45)
            8
            l.cx
            (l.ceilY + (l.floorY - l.ceilY) * 0.45)
            (opts.width * 0.78)
        )


rockCeiling : Options -> Layout -> C.Shape
rockCeiling opts l =
    C.rect 0
        (l.ceilY - 52)
        opts.width
        52
        (C.linear
            [ ( 0.0, "#40382b" ), ( 0.5, "#2c261e" ), ( 1.0, "#181510" ) ]
            0
            (l.ceilY - 52)
            0
            l.ceilY
        )


depthGrid : Options -> Layout -> C.Shape
depthGrid opts l =
    let
        stepM =
            gridStep opts.chamberM

        count =
            floor (opts.chamberM / stepM)
    in
    C.Groups <|
        (List.range 1 count
            |> List.map
                (\k ->
                    let
                        y =
                            toY l (toFloat k * stepM)
                    in
                    C.segment 0
                        y
                        opts.width
                        y
                        (C.dashed [ 2, 8 ] (C.stroke "rgba(255,255,255,0.06)" 1))
                )
        )


gridStep : Float -> Float
gridStep chamberM =
    if chamberM <= 0.35 then
        0.05

    else if chamberM <= 0.9 then
        0.1

    else if chamberM <= 2.2 then
        0.25

    else
        0.5


{-| The side of the formation catching the cave light.
-}
litFace : List ( Float, Float ) -> Layout -> C.Shape
litFace pts l =
    C.polygon
        (List.map (\( d, r ) -> ( l.cx - r * l.scale * 0.46, toY l d )) pts
            ++ List.map (\( d, r ) -> ( l.cx - r * l.scale * 0.6, toY l d )) (List.reverse pts)
        )
        (C.solid "rgba(255,247,228,0.18)")


{-| Annual layering etched across the surface. Each band is one year of
deposit, so their spacing is the local growth rate made visible.
-}
growthRings : Options -> Layout -> List ( Float, Float ) -> C.Shape
growthRings opts l pts =
    let
        n =
            List.length pts

        every =
            max 1 (n // 22)

        drawn =
            pts
                |> List.indexedMap Tuple.pair
                |> List.filter (\( i, _ ) -> modBy every i == 0)
                |> List.map Tuple.second
    in
    C.Groups <|
        (drawn
            |> List.map
                (\( d, r ) ->
                    let
                        y =
                            toY l d

                        x0 =
                            l.cx - r * l.scale * 0.94

                        x1 =
                            l.cx + r * l.scale * 0.94
                    in
                    C.segment x0 y x1 y (C.stroke "rgba(84,66,42,0.13)" 1)
                )
        )


{-| The water film: a bright lip on each side, slightly thicker and brighter at
the apex where the film is thinnest and freshest.
-}
waterFilm : List ( Float, Float ) -> Layout -> C.Shape
waterFilm pts l =
    C.Groups
        [ C.polyline (List.map (\( d, r ) -> ( l.cx + r * l.scale + 1.4, toY l d )) pts)
            (C.stroke "rgba(152,208,240,0.60)" 1.7)
        , C.polyline (List.map (\( d, r ) -> ( l.cx - r * l.scale - 1.4, toY l d )) pts)
            (C.stroke "rgba(152,208,240,0.34)" 1.3)
        ]


{-| A dome drawn over the apex, so the tip reads as a rounded cap rather than a
flat cut.
-}
capArc : Options -> Layout -> ( Float, Float ) -> List ( Float, Float )
capArc opts l ( d0, r0 ) =
    let
        pts =
            profilePoints opts.sim

        second =
            List.drop 4 pts |> List.head |> Maybe.withDefault ( d0, r0 )

        drop =
            max 0.00015 (Tuple.first second - d0)

        steps =
            18

        _ =
            opts
    in
    List.range 0 steps
        |> List.map
            (\k ->
                let
                    a =
                        pi * toFloat k / toFloat steps
                in
                ( l.cx + r0 * l.scale * cos a
                , toY l d0 - drop * l.scale * sin a * 0.85
                )
            )


{-| Falling drops. The rhythm follows the drip rate; the acceleration follows
gravity, so a slow drip visibly spaces the stream out.
-}
fallingDrops : Options -> Layout -> ( Float, Float ) -> List C.Shape
fallingDrops opts l ( apexDepth, apexR ) =
    let
        period =
            clamp 0.12 12.0 (P.dripIntervalFromRate opts.env.dripRate / 24.0)

        fall =
            max 0.05 (opts.chamberM - apexDepth)

        count =
            8
    in
    List.range 0 (count - 1)
        |> List.map
            (\k ->
                let
                    phase =
                        toFloat (modBy 1000 (round ((opts.time / period + toFloat k * 0.41) * 1000))) / 1000.0

                    -- constant acceleration: distance ~ phase^2
                    frac =
                        phase * phase

                    y =
                        toY l (apexDepth + fall * frac)

                    stretch =
                        1.0 + phase * 1.4

                    alpha =
                        clamp 0.05 0.9 (0.9 - phase * 0.6)
                in
                C.ellipse (l.cx + apexR * l.scale * 0.05)
                    y
                    (1.7 / sqrt stretch)
                    (2.4 * stretch)
                    (C.solid (C.rgba 158 210 242 alpha))
            )


{-| The stalagmite growing on the floor below.
-}
stalagmite : Options -> Layout -> C.Shape
stalagmite opts l =
    if opts.stalagmiteM <= 0.002 then
        C.Groups []

    else
        let
            h =
                min opts.stalagmiteM (opts.chamberM * 0.5)

            w =
                h * 0.9

            steps =
                18

            outline =
                List.range 0 steps
                    |> List.map
                        (\k ->
                            let
                                a =
                                    pi * toFloat k / toFloat steps
                            in
                            ( l.cx + w * l.scale * cos a
                            , l.floorY - h * l.scale * sin a
                            )
                        )

            closed =
                outline ++ [ ( l.cx - w * l.scale, l.floorY + 10 ), ( l.cx + w * l.scale, l.floorY + 10 ) ]
        in
        C.polygon closed
            (C.linear
                [ ( 0.0, "rgba(214,192,152,0.92)" ), ( 1.0, "rgba(104,88,66,0.92)" ) ]
                l.cx
                (l.floorY - h * l.scale)
                l.cx
                l.floorY
            )


axisLegend : Options -> Layout -> List C.Shape
axisLegend opts l =
    let
        barM =
            gridStep opts.chamberM

        px =
            barM * l.scale

        x =
            20.0

        y =
            l.floorY + 30

        lengthText =
            String.fromFloat (toHundredths (P.lengthOf opts.sim * 100)) ++ " cm"
    in
    [ C.segment x y (x + px) y (C.stroke Ui.dim 1.5)
    , C.segment x (y - 4) x (y + 4) (C.stroke Ui.dim 1.5)
    , C.segment (x + px) (y - 4) (x + px) (y + 4) (C.stroke Ui.dim 1.5)
    , C.label (x + px + 8) (y + 4) (String.fromFloat barM ++ " m") Ui.dim "left"
    , C.label (opts.width - 18) (y + 4) ("length " ++ lengthText) Ui.accent "right"
    ]


toHundredths : Float -> Float
toHundredths x =
    toFloat (round (x * 100)) / 100
