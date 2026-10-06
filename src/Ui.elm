module Ui exposing (..)

{-| Small view helpers: a dark "cave instrument" theme, sliders, buttons and
readout rows. Kept separate from `Main` so the scene drawing stays readable.
-}

import Html exposing (Html)
import Html.Attributes as A
import Html.Events as Ev



-- THEME


paper : String
paper =
    "#0a0c10"


ink : String
ink =
    "#e8eef6"


dim : String
dim =
    "#8b98a8"


faint : String
faint =
    "#5a6675"


accent : String
accent =
    "#e0b070"


accentSoft : String
accentSoft =
    "rgba(224,176,112,0.14)"


water : String
water =
    "#6fb3d8"


panelBg : String
panelBg =
    "rgba(18,22,29,0.92)"


ok : String
ok =
    "#79c98a"


warn : String
warn =
    "#e0805a"



-- LAYOUT


sheet : List (Html msg) -> Html msg
sheet =
    Html.div
        [ A.style "display" "flex"
        , A.style "flex-direction" "column"
        , A.style "gap" "14px"
        , A.style "padding" "14px"
        , A.style "background" panelBg
        , A.style "border" ("1px solid " ++ faint)
        , A.style "border-radius" "10px"
        , A.style "backdrop-filter" "blur(6px)"
        ]


section : String -> List (Html msg) -> Html msg
section title children =
    Html.div [ A.style "display" "flex", A.style "flex-direction" "column", A.style "gap" "8px" ]
        (Html.div
            [ A.style "font" "600 10px ui-monospace, monospace"
            , A.style "letter-spacing" "0.16em"
            , A.style "text-transform" "uppercase"
            , A.style "color" accent
            , A.style "opacity" "0.85"
            ]
            [ Html.text title ]
            :: children
        )


hint : String -> Html msg
hint t =
    Html.div
        [ A.style "font" "400 10.5px ui-sans-serif, system-ui, sans-serif"
        , A.style "color" faint
        , A.style "line-height" "1.45"
        ]
        [ Html.text t ]



-- SLIDER


slider :
    { label : String
    , value : Float
    , min : Float
    , max : Float
    , step : Float
    , format : Float -> String
    , note : Maybe String
    , onInput : Float -> msg
    }
    -> Html msg
slider cfg =
    Html.div
        [ A.style "display" "flex"
        , A.style "flex-direction" "column"
        , A.style "gap" "3px"
        ]
        [ Html.div
            [ A.style "display" "flex"
            , A.style "justify-content" "space-between"
            , A.style "align-items" "baseline"
            , A.style "gap" "8px"
            ]
            [ Html.span
                [ A.style "font" "500 11.5px ui-sans-serif, system-ui, sans-serif"
                , A.style "color" ink
                ]
                [ Html.text cfg.label ]
            , Html.span
                [ A.style "font" "600 11.5px ui-monospace, monospace"
                , A.style "color" accent
                , A.style "white-space" "nowrap"
                ]
                [ Html.text (cfg.format cfg.value) ]
            ]
        , Html.input
            ([ A.type_ "range"
             , A.min (String.fromFloat cfg.min)
             , A.max (String.fromFloat cfg.max)
             , A.step (String.fromFloat cfg.step)
             , A.value (String.fromFloat cfg.value)
             , Ev.onInput (\s -> cfg.onInput (Maybe.withDefault cfg.value (String.toFloat s)))
             , A.style "width" "100%"
             , A.style "height" "18px"
             , A.style "accent-color" accent
             , A.style "cursor" "pointer"
             ]
                ++ [ A.style "background" "transparent" ]
            )
            []
        , case cfg.note of
            Nothing ->
                Html.text ""

            Just n ->
                hint n
        ]



-- BUTTONS


button : Bool -> String -> msg -> Html msg
button active labelText msg =
    Html.button
        [ Ev.onClick msg
        , A.style "font" "600 11px ui-sans-serif, system-ui, sans-serif"
        , A.style "padding" "7px 11px"
        , A.style "border-radius" "7px"
        , A.style "cursor" "pointer"
        , A.style "border"
            ("1px solid "
                ++ (if active then
                        accent

                    else
                        faint
                   )
            )
        , A.style "background"
            (if active then
                accentSoft

             else
                "rgba(255,255,255,0.03)"
            )
        , A.style "color"
            (if active then
                accent

             else
                ink
            )
        , A.style "transition" "all 120ms"
        , A.style "white-space" "nowrap"
        ]
        [ Html.text labelText ]


buttonRow : List (Html msg) -> Html msg
buttonRow =
    Html.div
        [ A.style "display" "flex"
        , A.style "flex-wrap" "wrap"
        , A.style "gap" "6px"
        ]



-- READOUTS


row : String -> String -> String -> Html msg
row key value colour =
    Html.div
        [ A.style "display" "flex"
        , A.style "justify-content" "space-between"
        , A.style "align-items" "baseline"
        , A.style "gap" "10px"
        , A.style "font" "11.5px ui-monospace, monospace"
        ]
        [ Html.span [ A.style "color" dim ] [ Html.text key ]
        , Html.span [ A.style "color" colour, A.style "font-weight" "600", A.style "text-align" "right" ]
            [ Html.text value ]
        ]


rule : Html msg
rule =
    Html.div
        [ A.style "height" "1px"
        , A.style "background" faint
        , A.style "opacity" "0.4"
        , A.style "margin" "2px 0"
        ]
        []


badge : String -> String -> Html msg
badge colour t =
    Html.span
        [ A.style "font" "600 10px ui-monospace, monospace"
        , A.style "padding" "2px 7px"
        , A.style "border-radius" "999px"
        , A.style "border" ("1px solid " ++ colour)
        , A.style "color" colour
        , A.style "background" "rgba(255,255,255,0.03)"
        ]
        [ Html.text t ]


bar : Float -> String -> Html msg
bar fraction colour =
    Html.div
        [ A.style "height" "4px"
        , A.style "border-radius" "2px"
        , A.style "background" "rgba(255,255,255,0.07)"
        , A.style "overflow" "hidden"
        ]
        [ Html.div
            [ A.style "height" "100%"
            , A.style "width" (String.fromFloat (clamp 0 100 (fraction * 100)) ++ "%")
            , A.style "background" colour
            , A.style "border-radius" "2px"
            ]
            []
        ]
