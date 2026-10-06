module Canvas exposing
    ( Draw
    , Fill
    , Shape(..)
    , Stroke
    , circle
    , dashed
    , ellipse
    , encodeDraw
    , label
    , linear
    , polygon
    , polyline
    , radial
    , rect
    , rgb
    , rgbString
    , rgba
    , segment
    , solid
    , stroke
    , withAlpha
    )

{-| A minimal drawing layer over the HTML canvas 2D context.

The Elm side builds a pure value describing the scene; a single port hands it
to a small JavaScript renderer which walks the JSON and issues the canvas
calls. Elm never touches the DOM imperatively, and the whole scene is a value
that can be produced from the model in `view` or collected in `update`.

-}

import Json.Encode as E


{-| A gradient stop: position 0..1 and a CSS colour.
-}
type alias Stop =
    ( Float, String )


{-| Fill styles.
-}
type Fill
    = Flat String
    | Linear (List Stop) Float Float Float Float
    | Radial (List Stop) Float Float Float Float Float Float


{-| Stroke styles.
-}
type alias Stroke =
    { colour : String
    , width : Float
    , cap : String
    , dash : List Float
    }


{-| Every primitive the renderer understands.
-}
type Shape
    = Rect Float Float Float Float Fill
    | Circle Float Float Float Fill (Maybe Stroke)
    | Ellipse Float Float Float Float Fill (Maybe Stroke)
    | Poly Bool (List ( Float, Float )) Fill (Maybe Stroke)
    | Seg Float Float Float Float Stroke
    | Label Float Float String String String String
    | Groups (List Shape)


type alias Draw =
    { width : Float
    , height : Float
    , background : String
    , shapes : List Shape
    }


solid : String -> Fill
solid =
    Flat


{-| A linear gradient across the given endpoints.
-}
linear : List Stop -> Float -> Float -> Float -> Float -> Fill
linear =
    Linear


{-| A radial gradient, canvas style: two circles.
-}
radial : List Stop -> Float -> Float -> Float -> Float -> Float -> Float -> Fill
radial =
    Radial


{-| Turning a hex colour into an rgba string, so alpha can be applied in Elm
without a colour-parsing dependency.
-}
withAlpha : String -> Float -> String
withAlpha colour a =
    case String.toList (String.dropLeft 1 colour) of
        [ r1, r2, g1, g2, b1, b2 ] ->
            case ( hexPair r1 r2, hexPair g1 g2, hexPair b1 b2 ) of
                ( Just r, Just g, Just b ) ->
                    rgba r g b a

                _ ->
                    colour

        _ ->
            colour


hexPair : Char -> Char -> Maybe Int
hexPair a b =
    Maybe.map2 (\x y -> x * 16 + y) (hexDigit a) (hexDigit b)


hexDigit : Char -> Maybe Int
hexDigit c =
    case c of
        '0' ->
            Just 0

        '1' ->
            Just 1

        '2' ->
            Just 2

        '3' ->
            Just 3

        '4' ->
            Just 4

        '5' ->
            Just 5

        '6' ->
            Just 6

        '7' ->
            Just 7

        '8' ->
            Just 8

        '9' ->
            Just 9

        'a' ->
            Just 10

        'b' ->
            Just 11

        'c' ->
            Just 12

        'd' ->
            Just 13

        'e' ->
            Just 14

        'f' ->
            Just 15

        'A' ->
            Just 10

        'B' ->
            Just 11

        'C' ->
            Just 12

        'D' ->
            Just 13

        'E' ->
            Just 14

        'F' ->
            Just 15

        _ ->
            Nothing


stroke : String -> Float -> Stroke
stroke colour width =
    { colour = colour, width = width, cap = "round", dash = [] }


dashed : List Float -> Stroke -> Stroke
dashed d s =
    { s | dash = d }


rect : Float -> Float -> Float -> Float -> Fill -> Shape
rect =
    Rect


circle : Float -> Float -> Float -> Fill -> Shape
circle x y r f =
    Circle x y r f Nothing


circleOutlined : Float -> Float -> Float -> Fill -> Stroke -> Shape
circleOutlined x y r f s =
    Circle x y r f (Just s)


ellipse : Float -> Float -> Float -> Float -> Fill -> Shape
ellipse x y rx ry f =
    Ellipse x y rx ry f Nothing


polygon : List ( Float, Float ) -> Fill -> Shape
polygon pts f =
    Poly True pts f Nothing


polygonOutlined : List ( Float, Float ) -> Stroke -> Shape
polygonOutlined pts s =
    Poly True pts (Flat "rgba(0,0,0,0)") (Just s)


polyline : List ( Float, Float ) -> Stroke -> Shape
polyline pts s =
    Poly False pts (Flat "rgba(0,0,0,0)") (Just s)


segment : Float -> Float -> Float -> Float -> Stroke -> Shape
segment =
    Seg


label : Float -> Float -> String -> String -> String -> Shape
label x y content colour align =
    Label x y content "400 12px ui-sans-serif, system-ui, sans-serif" colour align


rgba : Int -> Int -> Int -> Float -> String
rgba r g b a =
    "rgba("
        ++ String.fromInt r
        ++ ","
        ++ String.fromInt g
        ++ ","
        ++ String.fromInt b
        ++ ","
        ++ String.fromFloat (toThousandths a)
        ++ ")"


rgb : Int -> Int -> Int -> String
rgb r g b =
    rgba r g b 1.0


{-| Alias kept for readability at call sites that build CSS colour strings.
-}
rgbString : Int -> Int -> Int -> String
rgbString =
    rgb


toThousandths : Float -> Float
toThousandths x =
    toFloat (round (clamp 0.0 1.0 x * 1000.0)) / 1000.0


encodeDraw : Draw -> E.Value
encodeDraw draw =
    E.object
        [ ( "w", E.float draw.width )
        , ( "h", E.float draw.height )
        , ( "bg", E.string draw.background )
        , ( "shapes", E.list encodeShape draw.shapes )
        ]


encodeShape : Shape -> E.Value
encodeShape shape =
    case shape of
        Rect x y w h f ->
            E.object
                [ ( "t", E.string "rect" )
                , ( "x", E.float x )
                , ( "y", E.float y )
                , ( "w", E.float w )
                , ( "h", E.float h )
                , ( "f", encodeFill f )
                ]

        Circle x y r f ms ->
            E.object
                [ ( "t", E.string "circle" )
                , ( "x", E.float x )
                , ( "y", E.float y )
                , ( "r", E.float r )
                , ( "f", encodeFill f )
                , ( "s", encodeMaybeStroke ms )
                ]

        Ellipse x y rx ry f ms ->
            E.object
                [ ( "t", E.string "ellipse" )
                , ( "x", E.float x )
                , ( "y", E.float y )
                , ( "rx", E.float rx )
                , ( "ry", E.float ry )
                , ( "f", encodeFill f )
                , ( "s", encodeMaybeStroke ms )
                ]

        Poly closed pts f ms ->
            E.object
                [ ( "t", E.string "poly" )
                , ( "closed", E.bool closed )
                , ( "p", E.list encodePoint pts )
                , ( "f", encodeFill f )
                , ( "s", encodeMaybeStroke ms )
                ]

        Seg x0 y0 x1 y1 st ->
            E.object
                [ ( "t", E.string "seg" )
                , ( "x0", E.float x0 )
                , ( "y0", E.float y0 )
                , ( "x1", E.float x1 )
                , ( "y1", E.float y1 )
                , ( "s", encodeStroke st )
                ]

        Label x y content font colour align ->
            E.object
                [ ( "t", E.string "label" )
                , ( "x", E.float x )
                , ( "y", E.float y )
                , ( "v", E.string content )
                , ( "font", E.string font )
                , ( "c", E.string colour )
                , ( "align", E.string align )
                ]

        Groups inner ->
            E.object
                [ ( "t", E.string "group" )
                , ( "shapes", E.list encodeShape inner )
                ]


encodePoint : ( Float, Float ) -> E.Value
encodePoint ( x, y ) =
    E.list E.float [ x, y ]


encodeFill : Fill -> E.Value
encodeFill fill =
    case fill of
        Flat c ->
            E.object [ ( "k", E.string "flat" ), ( "c", E.string c ) ]

        Linear g x0 y0 x1 y1 ->
            E.object
                [ ( "k", E.string "linear" )
                , ( "stops", encodeStops g )
                , ( "x0", E.float x0 )
                , ( "y0", E.float y0 )
                , ( "x1", E.float x1 )
                , ( "y1", E.float y1 )
                ]

        Radial g x0 y0 r0 x1 y1 r1 ->
            E.object
                [ ( "k", E.string "radial" )
                , ( "stops", encodeStops g )
                , ( "x0", E.float x0 )
                , ( "y0", E.float y0 )
                , ( "r0", E.float r0 )
                , ( "x1", E.float x1 )
                , ( "y1", E.float y1 )
                , ( "r1", E.float r1 )
                ]


encodeStops : List Stop -> E.Value
encodeStops g =
    E.list (\( p, c ) -> E.list E.string [ String.fromFloat p, c ]) g


encodeMaybeStroke : Maybe Stroke -> E.Value
encodeMaybeStroke ms =
    case ms of
        Nothing ->
            E.null

        Just s ->
            encodeStroke s


encodeStroke : Stroke -> E.Value
encodeStroke s =
    E.object
        [ ( "c", E.string s.colour )
        , ( "w", E.float s.width )
        , ( "cap", E.string s.cap )
        , ( "dash", E.list E.float s.dash )
        ]
