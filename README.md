# Stalactite

An Elm web app that grows a stalactite from the physics of calcite deposition,
with SvelteKit, Angular and Vue ports of the same thing.

All four are formula-for-formula the same model, and the three TypeScript ports
share one core file between them. `tests/physics.test.ts` in each checks that core
against values emitted from this Elm build, so the agreement is measured between
independent implementations rather than asserted:

```sh
cd svelte  && npm test       # 96 parity checks, plus 21 renderer checks
cd angular && npm test       # same suites, same numbers
cd vue     && npm test       # same suites, same numbers
```

The formation is not drawn from a formula: it is grown from a calcium budget.
Water arrives at the tip, runs back **up** the surface as a thin gravity-driven
film, loses CO₂ to the cave air, and precipitates calcite. Every mole of calcium
taken out of the film becomes one mole of calcite added to the solid.

## Run it

```sh
npm install          # elm and elm-format
npm run build        # elm make src/Main.elm --output=web/app.js --optimize
npm run serve        # http://127.0.0.1:4173
```

`npm run dev` builds without `--optimize`. The Elm compiler needs a writable
package cache; if `~/.elm` is not writable, set `ELM_HOME` to a local directory.

## Deployed

All three run the same physics and are deployed side by side:

| | Source | Live |
| --- | --- | --- |
| Elm | this repo | https://stalactite.stalactite.workers.dev |
| SvelteKit | [stalactite-svelte](https://github.com/leocrapart-pixel/stalactite-svelte) | https://stalactite-svelte.stalactite.workers.dev |
| Angular | [stalactite-angular](https://github.com/leocrapart-pixel/stalactite-angular) | https://stalactite-angular.stalactite.workers.dev |
| Vue | [stalactite-vue](https://github.com/leocrapart-pixel/stalactite-vue) | https://stalactite-vue.stalactite.workers.dev |

It is a Worker serving static assets from `web/` — the app needs no server-side
logic, so the Worker's only job is to hand back the built files. `wrangler.jsonc`
configures that, with `not_found_handling: single-page-application` so unknown
paths return `index.html` rather than a bare 404.

Redeploy after a change:

```sh
export CLOUDFLARE_API_TOKEN=...      # token with the "Edit Cloudflare Workers" template
export CLOUDFLARE_ACCOUNT_ID=...     # `npx wrangler whoami` prints it
npm run deploy                       # rebuilds Elm, then uploads
```

`npm run deploy:dry` validates the upload without publishing. Verify a deploy
serves the right thing before trusting it:

```sh
curl -s https://stalactite.stalactite.workers.dev/ | head
```

## What the model actually solves

| Step | Relation |
| --- | --- |
| Supply | `q` from the drip rate, in m³/s |
| Film | Nusselt thickness `h = (3 ν q / g P)^(1/3)` |
| Degassing | `k = D / h²`, so thin films shed CO₂ fastest |
| Chemistry | equilibrium calcium `c_eq` from the full carbonate system |
| Deposition | `R = k (c − c_eq)` per unit area |
| Shape | cone of fixed taper, its length derived from deposited volume |

### Chemistry

`caEq` solves the carbonate system properly rather than assuming a value. Henry's
law fixes dissolved CO₂; the two dissociation constants fix the speciation;
electroneutrality closes the system:

```
2 [Ca²⁺] + [H⁺] = [HCO₃⁻] + 2 [CO₃²⁻] + Kw/[H⁺]
```

That is a quadratic in the hydrogen ion concentration, solved by bisection on a
fixed pH 10 → pH 6 bracket. At 10 °C and 600 ppm the answer is **0.44 mM calcium
at pH 8.3** — the same order as drip water measured in real caves.

The three equilibrium constants (`Kc`, `K1`, `K2`) and the Henry constant use
van 't Hoff forms calibrated on their standard values at 25 °C. Getting these
wrong is not cosmetic: a linear empirical fit shifts the equilibrium calcium by a
factor of two, which is enough to turn a growing stalactite into a dissolving
one.

### Shape

The profile is a cone of fixed taper hung from the ceiling, so the radius at
depth `z` is `tipFloor + γz`. Everything about its size then follows from one
number, the accumulated calcite, because the cone volume can be inverted exactly:

```
V = (π/3) ( (a + γL)³ − a³ ) / γ
```

Solving that for `L` means the geometry is a function of the deposited volume, so
mass is conserved by construction and no timestep, however long, can outrun the
supply. The growth law that falls out,

```
dL/dt = f · q (c − c_eq) Ω / (π (a + γL)²)
```

carries its own slowing: as the cone widens, the same supply buys less length. A
stalactite grows quickly while it is thin and then appears to stall, which is what
uranium-series dating of real formations shows.

## Reading the panel

The right-hand column reports the quantities the model is really using — film
thickness, CO₂ degassing time, Reynolds number, supersaturation, depletion length
— so the result can be checked rather than trusted. If the drip water is at or
below equilibrium with the cave air, the app says so and nothing grows.

## Files

```
src/Physics.elm   the model: film, chemistry, geometry, time integration
src/Scene.elm     the cave cross-section, drawn from the profile
src/Canvas.elm    a small drawing layer over canvas 2D
src/Ui.elm        sliders, readouts, theme
src/Main.elm      application state, controls, readouts
js/main.js        canvas renderer and the port bridge
web/              built output and the page
```

`Physics` is pure: `step`, `advance` and `view` are ordinary functions with no
signals, ports or DOM, so the whole model can be exercised headlessly. The
`Check` harness used during development did exactly that.

## Caveats

These apply to both implementations.

* One stalactite receives the whole drip. In a real cave, water is shared between
  many formations, so growth rates here are upper bounds.
* The calcite exchange velocity `k` is exposed as a slider because the effective
  value over a whole formation is much smaller than laboratory thin-film
  measurements. Changing it changes the growth rate linearly.
* The tip is a rounded cap, but the model tracks its radius rather than solving
  the free-boundary problem for its exact profile.
* Stalagmites and columns are scenery, not simulated.
