# GTIndian Style Bible — Chennai (v1)

Numbers were measured by eye from the Wikimedia Commons reference set (`data/refs/refs.json`, contact sheets in `data/refs/images/`, which are local-only and not shipped). Where a value comes from published traffic studies or general knowledge rather than the images, it is marked *(est.)*. The generators in `src/world/` read these numbers from `public/packs/chennai/style.json`. Keep this document and that JSON in sync.

Reference IDs are Commons page IDs, e.g. `23467177` is Georgetown area 1.

---

## 1. Light and atmosphere
| Item | Rule |
|---|---|
| Daytime sky | Rarely deep blue. Zenith `#a9c2dc`–`#bccfe0`, and the horizon washes to near-white `#dfe2e2`. On 60% of days a thin overcast or haze layer is present (refs 120606431, 55333571). |
| Haze | Visibility of about 1.5–3 km. FogExp2 density 0.0018 at noon and 0.003 at dawn. Fog colour tracks the sky horizon, not grey. |
| Noon sun | Near-vertical (13°N). Short, hard shadows; sun intensity is the highest key (3.6). Walls read bleached. |
| Golden hour | 17:15–18:10. Sun `#ffc27a` → `#ff8a48`. Dusk is short: dark about 40 minutes after sunset. |
| Night | The sky is never black: dark navy `#0a0d18` overhead fading to sodium-orange glow `#2c1b10` at the horizon (city light pollution). Few stars. |
| Night lights | Street lights are a mix of 60% LED white (5000K, `#e8f0ff`) on main roads and 40% sodium (`#ffb050`) on old and interior streets. Shops use cool-white tube lights `#eef6ff`, 1–3 per shop front, placed horizontally above the shutter. |
| Wet | After rain, roads are dark and glossy (roughness 0.15). Puddles collect at road edges and in potholes. |

## 2. Buildings
### Heights (G = ground floor; G+2 = 3 floors)
| Context | Distribution |
|---|---|
| Mylapore old core (≤420 m from the Kapaleeshwarar temple), agraharam row houses | G 45%, G+1 45%, G+2 10%. Footprint 4–7 m wide × 12–25 m deep. |
| Residential lanes (Mandaveli, Luz) | G 8%, G+1 32%, G+2 34%, G+3 18%, G+4 8% |
| Commercial frontage on main roads (refs 120608107, 23467177) | G 6%, G+1 26%, G+2 34%, G+3 22%, G+4 12% |
| Apartments (footprint > 550 m²) | G+3 15%, G+4 35%, G+5 25%, G+6 15%, G+7 10% |
| Floor-to-floor | 3.1 m residential; the commercial ground floor is 3.6–4.2 m |
| Parapet | A 0.9–1.1 m solid parapet on flat roofs, often with a decorative cut-out or painted band |

### Façade anatomy
- **Chajja (sunshade):** a concrete slab 0.45–0.6 m deep above *every* window and door. This is the single most important Indian façade cue. A black rain-streak stain runs 0.3–1.2 m down from each chajja end.
- **Windows:** 1.2 × 1.35 m on average, with 2–3 per 4 m of wall. About 70% have MS grilles (square, diamond or floral patterns) painted black, green or grey. Wooden shutters appear on old houses; aluminium sliding windows appear on post-2000 buildings.
- **Balconies:** 35% of residential floors have a 0.9–1.2 m projecting balcony with an MS-grille or concrete-jaali railing, and clothes drying on 40% of them.
- **AC units:** on 30–50% of upper-floor windows in commercial blocks, and 15% in residential. Units are mounted outside on brackets, with a drip stain below.
- **Roof clutter (per roof):** 1–3 black plastic water tanks (Ø1.1–1.5 m, height 1.2–1.6 m) on 80% of roofs, a staircase headroom box (mumty) on 70%, a dish antenna on 40%, clothes lines on 25%, and a mobile tower on 1 in 60 buildings in commercial areas.
- **Exposed services:** PVC drain pipes run down the façade (2–4 per building) and the electrical meter board sits at ground level.

### Paint palette (sRGB; apply ±8% value jitter and 0–25% weathering darkening)
- **Limewash pastels (residential):** `#efe3c4` cream, `#e9d39a` ochre-yellow, `#e7c3a6` peach, `#d9e4d0` mint, `#cfdbe3` pale blue, `#e6cfd8` pale pink, `#f2efe7` off-white, `#e3d7bf` beige.
- **Commercial blocks:** `#e8d29a`, `#d9a07a` salmon, `#c9c2b6` grey cement (unpainted is common), `#f0dcb0`, `#b7c7c9`.
- **Old-core accent:** `#c8553d` red-oxide (floors and window frames), `#2f6a5a` deep green (wooden doors), `#5b3a29` teak.
- **Temple compound walls:** alternating vertical *kaavi* (red-ochre `#b5442c`) and white `#f3efe6` stripes, each stripe 0.45–0.6 m wide. This is mandatory around temple and tank perimeters.

### Weathering (every building)
- Vertical black and grey streaks below chajjas, parapets and AC units. Streak coverage of the wall area is 10–35%.
- A damp band 0–0.8 m above ground, 20–40% darker with a green-grey tint.
- Repainting patches (a rectangle of slightly different paint) on 30% of façades.
- On old houses, peeling paint that exposes grey plaster.

## 3. Shop fronts (busy-street minimums from BRIEF §15)
- **Bay width:** 2.8–4.5 m (mean 3.4). On commercial frontage, one shop per bay, so about 25–30 shops per 100 m counting both sides.
- **Anatomy, top to bottom:** signboard (flex or painted, 0.9–1.5 m high, full bay width, often projecting 0.1 m), then 1–3 tube lights, then a sloped tin or tarpaulin awning (0.8–1.5 m deep) on 50% of shops, then a rolling shutter housing, then the open shop with stock to the back wall, then goods spilling 0.5–2 m onto the footpath (crates, stands, display racks), then 1–2 plastic stools or chairs.
- **Signboards:** Tamil **first and largest**, with the English transliteration or name below or alongside it (Tamil Nadu signage rule). Of the boards, 60% are printed flex (saturated backgrounds: red, blue, green, yellow, with photographic product images) and 40% are hand-painted (enamel on tin, simpler 2–3 colour palette, serif or bold sans lettering). A building's upper floors carry 2–6 extra boards (tuition, clinic, offices), as in refs 120608107 and 23467177.
- **Stock by trade:** fruit (stacked pyramids and hanging banana bunches; ref 33160727), flower (jasmine strings and garlands hung on poles), provision (sacks, hanging sachets, jars), textiles (folded stacks and hanging sarees), pooja (brass items, garlands), tea (glass jars of biscuits, steel tumblers, a big boiler), mobile (a glass counter and posters).
- **Plastic crates** (red `#c62828`, blue `#1565c0`) appear at 70% of food shops.

## 4. Streets and roads
| Element | Rule |
|---|---|
| Carriageway | Primary roads 12–14 m, secondary 9–10 m, residential 5–6 m, old-core lanes 3.5–4.5 m |
| Footpath | Main roads have 1.2–2.5 m footpaths, kerbed 0.15–0.2 m, with broken pavers on 20% of the length. About 50% of the footpath width is occupied by shops, vendors or parked bikes, so pedestrians walk in the carriageway. Residential lanes have no footpath. |
| Asphalt | Base colour `#3a3a3a` (new) to `#5a5853` (old, dusty). Patch repairs cover 8–15% of the area as darker rectangles. Potholes (0.3–1.2 m) occur at 2–6 per 100 m on residential streets and 0–2 on primary roads. |
| Markings | Faded white centre dashes (3 m dash, 4.5 m gap) only on secondary roads and above. Zebra crossings at signals. About 40% of markings are worn to invisibility. |
| Speed breakers | Every 80–150 m on residential streets. 50% are painted with black and yellow stripes and 50% are unpainted. |
| Medians | On primary roads: 0.6 m concrete, painted black and yellow, with gaps every 150–250 m. |
| Street lights | Every 25–35 m on main roads, every 40–60 m on lanes (often on electricity poles). |
| Overhead cables | 4–12 cables per 30 m crossing old-core streets, sagging 0.5–1.5 m, attached to buildings and poles. Festival bunting and political flag strings appear on 20% of streets (ref 23467178). |
| Poles | Concrete electricity poles every 30–40 m, carrying transformer boxes and junction boxes, and plastered with posters. |
| Drains | Open storm drains along the road edge with RCC slab covers 0.6 × 1 m. 10% of the slabs are broken. |
| Parked two-wheelers | Dense rows angled at 60–80° along the kerb outside shops (ref 37505740). This is a defining feature. |

## 5. Vehicles and traffic mix (share of moving vehicles; est. from Chennai traffic studies and refs)
| Road type | 2W | Auto | Car | Bus | LCV/Truck | Cycle | Other |
|---|---|---|---|---|---|---|---|
| Primary | 48% | 12% | 26% | 5% | 5% | 3% | 1% |
| Secondary | 52% | 14% | 22% | 3% | 4% | 4% | 1% |
| Residential | 58% | 15% | 14% | 0% | 3% | 8% | 2% (handcarts, cattle) |
| Old core / temple streets | 55% | 22% | 8% | 0% | 3% | 8% | 4% |

- **Autos:** the body is Chennai yellow `#f2b705`–`#f4c20d` with a black or dark-green canvas roof and a green or black lower stripe. Every auto carries stickers, a slogan or a deity picture on the back panel. Licence-style plates have a yellow background (commercial). See ref 19778423.
- **City buses** (fictional *MNT*, Maanagara Naveena Transport): older stock is blue `#2a5db0` with a worn white band; newer low-floor stock is metallic green and white. The destination board is Tamil above English (ref 15681380).
- **Two-wheelers:** commuter bikes and scooters in black, grey, red and blue. 40% carry a pillion, 8% carry three people. Women riding pillion sit side-saddle 60% of the time.
- **Horn rate:** each moving vehicle honks every 4–12 s in congestion and every 15–30 s on clear roads.

## 6. People
- **Density:** temple streets at evening run 0.4–0.8 people/m² near the temple gates. Commercial footpaths run 0.15–0.3. Residential lanes run 0.02–0.06.
- **Dress, men:** 40–55% shirt and trousers. 15–25% veshti, white or cream with a thin coloured or gold border. 15–20% lungi (checked: blue, maroon or green). 10–15% T-shirt and jeans. Elders are more traditional. A towel over the shoulder is common among older men and workers.
- **Dress, women:** 50–65% saree (synthetic or cotton, saturated colours with a contrast or gold border), 25–35% churidar or salwar with a dupatta, and 5–10% western. Jasmine in the hair on 50%.
- **Children:** school uniforms at 07:30–08:30 and 15:30–16:30 (white or light shirts; navy, maroon or green shorts and skirts; plaited hair with ribbons).
- **Skin:** a range of nine tones from wheatish `#c99c78` to deep brown `#4d3020`, weighted to the middle. There is no correlation with role, wealth or virtue.

## 7. Landmarks, Mylapore and Marina
- **Kapaleeshwarar temple** (refs 37505733, 47272630): the east rajagopuram rises about 37 m with 7 tiers, painted polychrome stucco crowded with figures (blue `#2b6cb0`, green `#2f9e44`, red `#c92a2a`, yellow `#f2c94c`, pink `#e88aa8`, white). The kalasam finials are gold. The courtyard is granite flagstone, grey `#8a8580`, glossy when wet. Mandapam pillars are carved granite. The entrance arch over the street carries Nandi and deity stucco on top.
- **Temple tank** (Kapaleeshwara Koil Kulam, from OSM): about 190 × 150 m, with granite steps descending on all four sides (0.25 m risers), a central neerazhi mandapam on a plinth, and kaavi-and-white striped perimeter walls. The water is green-grey `#4a5a48`.
- **Marina** (refs 1952452, 55333571): the sand belt between Kamarajar Salai and the surf is 250–400 m wide. Sand is `#d8c49a` (dry) to `#9a8462` (wet). A few palmyra and coconut trees stand on the road side. Light poles are 12 m high with 4 heads. The sea is grey-green `#5d7066` with 2–4 white surf lines. Fishing catamarans sit on the sand to the south (Santhome). Vendor carts concentrate 16:00–21:00.
- **Lighthouse:** 45.7 m, a slender triangular-section tower with red and white bands (from OSM height).

## 8. Kolam
- White rice-flour linework, 0.6–1.8 m across, on swept and wetted ground at the doorsteps of 70% of houses in old-core and residential lanes by 07:00. Patterns are dot-grid loops (sikku), floral and geometric (ref 23467735). About 20% have a red border or centre. They fade to 30% opacity by 14:00 and are trampled away on busy streets.

## 9. Clutter quotas per 100 m of busy street (BRIEF §15 minimum, enforced by `tools/audit/density.mjs`)
≥15 shop fronts or stalls · ≥30 props · ≥5 posters or flex boards · overhead cable tangle present · ≥3 night light sources · parked two-wheeler rows · 1–2 street vendors · 0–2 cattle or dogs.

## 10. Political and commercial parody rules
- **Parties** (fictional; checked against real TN parties and their symbols — DMK sun, AIADMK two leaves, PMK mango, DMDK drum, MDMK top, VCK pot, MNM torch, AMMK cooker, NTK, TVK, plus national lotus/hand/sickle; and against non-TN symbols that read as real such as the RJD lantern and BJD conch):
  - **Tamizh Makkal Ezhuchi Kazhagam (TMEK)**, led by Aadhavan. Flag: horizontal maroon `#7a1f3d` over teal `#1f7a74` with a white **lighthouse** emblem. Slogan: "Ezhunthu Vaa!" (Rise up!)
  - **Anaithu Tamizhar Munnani (ATM)**, led by Nagaraj. Flag: sky blue `#4fa3d9` / white / yellow `#f2c230` vertical tricolour with a black **palmyra tree** emblem. Slogan: "Ellorukkum Ellam" (Everything for everyone). Yes, the acronym is ATM. The rival party mocks it.
  - Neither uses black-red, red-black-white, red-yellow, saffron-white-green or any real symbol. Cut-outs show fictional leaders only.
- **Brands:** all fictional. For example, "Thangam Gold Loan", "Kesavardhini Hair Oil", "Annai Rice", "Rocket 4G", "Kaapi Kudil", "Velan Silks".
