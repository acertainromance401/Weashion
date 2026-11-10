# Six source-derived Meshy garments

All six Desktop sources were opened read-only. Independent persisted-resource validation rechecked their SHA-256 hashes, finite coordinates, indices, positive triangle areas, ordered actual boundary loops, bindings and vertex/triangle limits. No existing source, Swift, catalog, README or pre-existing Blender resource was edited by these converters.
The latest metadata-only validation reused the previously independently verified original SHA evidence (`sourceHashRechecked:false`) rather than reopen cloud-backed Desktop originals. Fresh rehashing remains the validator's default; `--derived-only` explicitly scopes a metadata/derived-only pass. 

## Reproduce

From repository root (Blender 5.2.2 LTS):

```sh
/Applications/Blender.app/Contents/MacOS/Blender -b --python-exit-code 1 --python weashion/reference/garments/convert_garments.py
/Applications/Blender.app/Contents/MacOS/Blender -b --python-exit-code 1 --python weashion/reference/garments/repair_slivers.py -- --apply
/Applications/Blender.app/Contents/MacOS/Blender -b --python-exit-code 1 --python weashion/reference/garments/bind_sleeve_centerlines.py
/Applications/Blender.app/Contents/MacOS/Blender -b --python-exit-code 1 --python weashion/reference/garments/refine_hoodie_sleeves.py -- --apply
/Applications/Blender.app/Contents/MacOS/Blender -b --python-exit-code 1 --python weashion/reference/garments/narrow_hoodie_sleeves.py -- --apply
python3 weashion/reference/garments/validate_garments.py
/Applications/Blender.app/Contents/MacOS/Blender -b --python-exit-code 1 --python weashion/reference/garments/verify_blends.py
python3 weashion/reference/garments/write_report.py
```

`--only <id>` converts one asset; `--from-garment <id>` resumes the specified sequential order. `refresh_bindings.py`, run with Blender, remeasures existing runtime geometry without resimplification; if used, run it before numerical repair. `repair_slivers.py` without `--apply` performs a read-only dry run; `--only <id>` scopes it. It reads only the derived JSON/blends and is a no-op on already-repaired geometry. The converter now automatically runs numerical repair followed by sleeve-centerline authoring; the two explicit follow-up commands are also safe, idempotent derived-only rebuild steps. Hashing uses read-only mmap: conventional read()/shasum timed out on macOS compressed,dataless Desktop placeholders, whereas native Blender loading and mmap read the complete original bytes correctly. No source copy/cache is required.

## Optimization and fidelity

The latest hoodie-only art adjustment narrows bilateral sleeve width/depth by up to 20%, easing out at shoulder and cuff transitions. It preserves the hood, central torso, cuff loops, length/sizing/centerline bindings, and all 8,669 vertices / 16,792 triangles; 3,491 vertices move by at most 27.36 mm. The Meshy source hash is unchanged. [Measurements](hoodie_narrowing_report.json) and [before/after preview](hoodie_narrowing_comparison.png) describe this intentional shape change; earlier source-fidelity/native-fit renders and measurements below predate it. Resource validity, float32 size-edit margins and persisted Blend/JSON parity passed. Native/UI fitting and physical-device adjustment were not rerun at the user's request. The narrowing script refuses to apply twice; restore its recorded backup before authoring a different reduction.

All geometry comes from the named original meshes, not generic procedural garments. Source geometry is first normalized to editable adult sample dimensions; fidelity is measured **after this explicit dimensional/pose normalization**, not against the sources' arbitrary unit scale or splayed jeans stance.

Source-frame connected inward-wall removal protects every source face directly visible along a normal-facing cardinal ray. Small negative-normal wrinkle patches are retained; hidden opposing torso/leg walls are removed, small defects repaired, and true cuff/hem openings cut. Visible hood/bomber lining and relief remain source-derived; these local lining folds are not a second complete inner torso shell. Sneakers remain rigid, including their source soles, tongues, collar cavities and laces.

Candidates use quadric edge collapse with budgets 3000/4500/6000 vertices (8000/11000 available if needed). Actual counts differ because boundary/manifold repair is retained. The smallest measured passing candidate is selected, not a universal count. Skin reverse p95 thresholds are 0.30 mm for dress pants/sneakers, 0.45 mm for hoodie/jeans/bomber, and 2.2 mm for the long sleeve; every candidate also requires max <12 mm and 192px front/side/three-quarter silhouette IoU >97.5%. The shirt actually achieves submillimetre p95.

| Asset | Source vertices / triangles | Final runtime vertices / triangles | Vertex reduction | Pre-repair skin p95 mm | Pre-repair full-source front / back / side p95 mm | Pre-repair minimum full-source silhouette IoU |
|---|---:|---:|---:|---:|---:|---:|
| long_sleeve | 154,891 / 309,790 | 3,066 / 5,881 | 98.02% | 0.485 | 0.692 / 0.689 / 1.830 | 98.465% |
| hoodie | 218,964 / 437,946 | 8,669 / 16,792 | 96.04% | 0.336 | 0.548 / 0.459 / 1.249 | 98.655% |
| dress_pants | 151,653 / 303,369 | 4,665 / 8,235 | 96.92% | 0.260 | 0.514 / 0.448 / 0.459 | 99.511% |
| jeans | 172,217 / 344,466 | 4,700 / 8,705 | 97.27% | 0.417 | 1.085 / 0.755 / 0.854 | 99.311% |
| bomber | 465,473 / 931,244 | 6,040 / 11,409 | 98.70% | 0.327 | 0.771 / 0.664 / 1.552 | 98.256% |
| sneakers | 597,584 / 1,195,517 | 6,117 / 11,374 | 98.98% | 0.235 | 1.242 / 0.853 / 0.384 | 99.724% |

### Numerical normalization repair

The original derived meshes contained microscopic slivers close to the engine's cross-squared >1e-14 m⁴ rejection threshold. Ordinary smaller sizes exposed that insufficient margin. A bounded derived-only pass now targets 1.25e-12 internally and independently requires every exported/saved float32 triangle to remain ≥1e-12. The runtime threshold is unchanged. Long sleeve already met the margin and is unchanged.

The repair uses local topology-checked endpoint collapses, almost-coplanar edge rotations and constrained vertex/patch adjustments; no failing faces are silently skipped. Connected-component count, Euler characteristic and every existing ordered boundary loop are preserved, including small source feature slits, not just major cuffs/openings. Kept binding values are copied exactly and reindexed; actual cuff centres/perimeters are refreshed if needed. Sole thickness, per-foot dimensions and anchors remain unchanged. Kept vertex displacement is capped at .750 mm. One microscopic sneaker fold changes its geometric normal orientation during unfolding without reversing triangle winding; sound neighbouring faces retain their orientation.

| Asset | Before → after vertices / triangles | Min source cross² m⁴ | Min .8-scale cross² m⁴ | Worst sampled cleanup error mm | Boundary loops preserved |
|---|---:|---:|---:|---:|---:|
| long_sleeve | 3066/5881 → 3066/5881 | 1.4915e-12 | 6.1084e-13 | 0.000 | 4 |
| hoodie | 6077/11600 → 6068/11590 | 1.2668e-12 | 5.1887e-13 | 0.674 | 8 |
| dress_pants | 4725/8310 → 4665/8235 | 1.2565e-12 | 5.1466e-13 | 0.722 | 70 |
| jeans | 4715/8720 → 4700/8705 | 1.2539e-12 | 5.1360e-13 | 0.683 | 61 |
| bomber | 6050/11420 → 6040/11409 | 1.2541e-12 | 5.1367e-13 | 0.814 | 13 |
| sneakers | 6490/11804 → 6117/11374 | 1.2501e-12 | 5.1202e-13 | 0.930 | 450 |

All six pass float32-output checks at uniform .8 scale and anisotropic [.70,.75,.70]. The repair report also records actual catalog S/M/L resize mirrors and custom small pants (.72 waist/.90 hip/.23 rise/.68 inseam/.50 thigh/.30 hem metres), plus a 240×92 mm shoe. Mirrors implement the integrating Swift resize equations with float32 output, but are not a claim that the native Swift/body-fit suite was run here.

Cleanup fidelity is bidirectional nearest-surface sampling at **all vertices, triangle centroids and three edge midpoints**, not an exact Hausdorff bound. Per-asset and `sliver_repair_report.json` retain RMS/p95/max, operations, before/after hashes and case minima. The largest sampled change is <.930 mm, with .0354 mm worst p95. This is the explicit numerical-stability tradeoff: microscopic relief/fold tips soften slightly, but components, openings and recognizable features are not discarded.

Candidate/full-source fidelity numbers and original source-comparison renders above refer to the pre-cleanup selected geometry; they were **not** expensively rerun or misrepresented as new measurements. Final counts include cleanup. New `<id>_sliver_repair.png` and `_back.png` compare previous derived mesh left against repaired mesh right (reversed screen positions from the back); sneakers also have `_elevated.png`. No new repair preview is needed for unchanged long sleeve.

The full-source exterior test compares first-hit depth along 96×96 orthographic rays per view. It also reports RMS and **unclipped maximum** errors in each JSON report. Large isolated maxima occur at deliberately opened cuffs/hems, very thin laces, grazing silhouettes or rays falling through to a distant rear surface/other limb; they are not concealed or mistaken for Euclidean cloth-surface error. `rawSourceToRuntime` additionally includes intentionally discarded inner walls and caps, so its errors are not used to pretend those surfaces remain. Reports preserve every candidate's actual RMS/p95/max errors and silhouette scores.

## Runtime coordinate and measurement conventions

All JSON and editable Blender mesh coordinates are identical: metres, +Y up, +Z forward. Upper shoulder anchors are near Y=0, hem Y=-reference.length; collar/hood may extend above zero. Hood vertices above the shoulder and the overlapping upper rear hood are explicitly shoulder-bound, never sleeve-bound. Body references remain [hip .98, waist .82, chest .98] m; the actual garment section envelopes are separate.

### Source sleeve centerlines

All three uppers include top-level `sleeves:{right:[{center,station}],left:[...]}`. Actual left/right closed skin sections are measured independently, not imposed mirror copies. Centers are native coordinates (left X negative); final centers are actual ordered cuff-loop means. Stations are monotonic side-specific measurement-shoulder to actual-cuff chord projections, with both final stations exactly the canonical right reference sleeveLength. Long/hoodie have13 knots per side; bomber12. Measurement anchors, every mesh/trim index and every existing sizing/fit weight remain unchanged.

`bind_sleeve_centerlines.py` runs after numerical repair; its provenance and serialized `sleeves` custom property are saved in each optimized Blend. `sleeve_binding_report.json` records section circumferences, chord conventions and hashes. The independent validator checks actual cuff means and positive source-front depth/radius for triangle4991; saved Blend validation also ray-checks both source walls from every non-cuff center. The source curve is not the shoulder→cuff chord: the latter sits outside proximal long/bomber sleeve lumens. Cap armBlend remains distinct from axial station, and the runtime must resize source curves consistently and transport smooth frames. See `upper_sleeve_diagnostic.md` for evidence/limitations; native retargeting is integrated separately.

Closed torso/hip/thigh measurements use 128 ordered horizontal radial intersections with the actual garment shell, not a hull containing disconnected sleeves. Open bomber sections use connected mesh-plane intersections spanning both sides of the torso, excluding separate sleeves, then close their convex measurement envelope across the front gap **only for measurement**; no fake front faces are added. Sleeve-opening circumference is the ordered three-dimensional cuff boundary length. Trouser waist/hem sizes use the horizontal convex aperture envelope of the actual boundary vertices: raw meandering edge length exaggerates irregular generated rims and is not a useful wearer-fit circumference. Source asymmetry is preserved; right-side dimensions serve as editable symmetric sample references, not verified product sizing.

| Upper | Length | Shoulder | Chest | Waist | Hip | Sleeve shoulder→cuff centre | Right cuff circumference |
|---|---:|---:|---:|---:|---:|---:|---:|
| long_sleeve | 0.692074 | 0.460000 | 1.038388 | 0.999598 | 1.000080 | 0.610062 | 0.195977 |
| hoodie | 0.692201 | 0.520000 | 1.184740 | 1.098474 | 1.057700 | 0.600005 | 0.180441 |
| bomber | 0.652059 | 0.500000 | 1.158623 | 1.102785 | 1.040077 | 0.620117 | 0.198233 |

The schema's sleeve length is shoulder-anchor to ordered cuff-loop centre; it is not a flat-lay outside-edge tape measurement. Exact anchors and section centres/half extents are in runtime JSON and per-asset reports. Small differences from requested sample targets reflect genuine source boundaries, cap removal and asymmetric cuff folds; consumers must use the exported reference consistently rather than silently relabeling it.

Pants have waist Y=0 after opening/rebasing; crotch Y=-rise and lowest hem Y=-(rise+inseam). The 8 mm source-rim cut is reflected in actual rise. Right-leg centres are finite, positive X, strictly increasing Y from hem toward crotch; source splay is removed independently of per-leg shape. Leg weights smoothly transition from pelvis 0 to below-crotch 1.

| Bottom | Waist | Hip | Rise | Inseam | Right thigh | Right hem loop |
|---|---:|---:|---:|---:|---:|---:|
| dress_pants | 0.810888 | 1.024731 | 0.272000 | 0.752012 | 0.597545 | 0.377175 |
| jeans | 0.837368 | 1.017234 | 0.252000 | 0.772014 | 0.579227 | 0.357458 |

### Sneakers

Both source shoes are retained, labeled -1/+1 per vertex. Per-shoe external length is .270 m and width .105 m; each shoe is normalized independently, never by stretching the pair gap. `rightCenter=[.09,0,0]`, `leftCenter=[-.09,0,0]` are external bounding-box X/Z midpoints on the sole floor Y=0 (not ankle joints). +Z points toward toes.

`soleThickness=0.0348` m is an **estimated** sole-floor→heel/insole seating height from 20 downward ray hits in the source heel opening, range 0.034677–0.035027 m. This is a geometric seating recommendation, not a certified physical sole measurement (allow several millimetres of uncertainty). Place the body's foot floor at shoe-sole Y + this constant; keep it constant through length/width edits. An elevated comparison render exposes the tongues, laces and sole profile for visual checking.

## Deliverables and limitations

For every ID: `Resources/meshy_<id>.json`, `reference/garments/meshy_<id>_optimized.blend`, `<id>_report.json`, `<id>_comparison.png`, `<id>_comparison_back.png`. Front comparison: normalized original left, runtime right. Back view reverses those screen positions. Sneakers also include an elevated comparison. Blender files contain the editable runtime mesh, smooth shading, upper-region/Sleeve vertex groups, source hash and sample-measurement properties; no external textures or rig dependencies.

No UV/image maps or rigs existed in these six sources. Pocket seams, lace facets, tiny stitch/rib relief and bomber quilt microrelief soften at these budgets; the reports do not claim lossless geometry. Representative source folds, openings, hood, pockets, sole/lace silhouettes and open bomber front remain. This is an editable starting mesh, not production sewing topology or a guarantee of correct arbitrary-body cloth drape; native app/body-fit and solver validation remains the integrating engine's responsibility.

Independent `validation_report.json` records resource/source hashes, zero unused vertices, strict runtime triangle cross-squared >1e-14 with authored float32 margin ≥1e-12, representative smaller-edit minima, zero duplicate triangles/nonmanifold edges, ordered boundary-loop validity, finite normalized bindings and limits. Desktop originals are byte-for-byte unchanged.

## Accepted hoodie sleeve-resolution refinement

The source-faithful skin was further refined from 6068 vertices/11590 triangles to **8669 vertices/16792 triangles**. This adds 2601 midpoint vertices and 5202 triangles, touching only 1264 original sleeve/cap faces; it is not a whole-garment remesh or a higher visual-detail budget.

The measured-centerline retargeting fixed the source-axis spikes, but native face contact still found a long hoodie triangle straddling a forearm despite clear corners. The candidate adds geometric degrees of freedom by conforming longest-edge bisection where edge midpoints have |X|>0.271731 m and Y<−.10 m, stopping at25 mm. Neighbouring triangles sharing a split edge are refined together; there are no hanging nodes. All original positions and weights are exact unchanged prefixes. Added weights are endpoint interpolations, not cap promotion to armBlend1.

Original face685 (79.708 mm longest edge) becomes9 descendants with maximum edge19.927 mm; faces923/941 each become3 descendants with maximum24.465 mm. All targeted edges are≤25 mm with no area-blocked exceptions. Eight opening loops, component/Euler topology, actual independent sleeve curves, sizing, material and original source geometry are preserved. Maximum child-to-original-face plane error is 8.413e-17 m. The authored float32 cross² minimum remains1.26677e-12; source, actual catalog S/M/L resize mirrors, uniform.8 and anisotropic smaller-shape checks pass.

Native integration accepted this refinement with solver22: standard M sampled overlap was approximately0.5 mm, with no vertex or face-centroid penetration over3 mm in that smoothed display surface. Standard M long/hoodie/bomber also passed the visible-edge extension regression. These native checks are separate from conversion fidelity and are not a guarantee of correct arbitrary-body cloth drape; see the repository README and native comparison metrics for current solver results and remaining cases. Geometry/Blend persistence checks pass. The previous hoodie derivative—not a Desktop source copy—is backed up at `/Users/acertainromance401/.copilot/session-state/4b7bdc14-ebc0-424e-98c5-262ab8fbe7f2/files/hoodie_before_sleeve_refinement_4ade2299a549.zip`. `hoodie_refinement_report.json` records exact face mappings, counts, hashes and limits.

To reproduce from the unrefined derivative, after source conversion/cleanup/sleeve binding:

```sh
/Applications/Blender.app/Contents/MacOS/Blender -b --python-exit-code 1 --python weashion/reference/garments/refine_hoodie_sleeves.py -- --apply
```

Omit `--apply` for a non-publishing candidate check. Already-refined derivatives are a no-op. This is a separate required hoodie-only post-conversion step; it does not modify any other garment or relax runtime thresholds. Future rebuild backups use the platform temporary directory rather than a machine-specific session path.

## Candidate evidence and original hashes

### long_sleeve

`Gray Long Sleeve Shirt_Meshy_AI_2026-10-28_95f43f.blend`
SHA-256 `87860987bcb737a1db8d4b544bb0f7414d3969c8d42f095dc48bb20bf8d56bf4`

| Budget | Actual vertices / triangles | Skin RMS / p95 / max mm | Min skin silhouette IoU | Pass |
|---:|---:|---:|---:|---|
| 3000 | 3066 / 5881 | 0.250 / 0.485 / 1.026 | 99.833% | True |
| 4500 | 4549 / 8823 | 0.161 / 0.316 / 0.636 | 99.881% | True |
| 6000 | 6028 / 11765 | 0.109 / 0.222 / 0.435 | 99.918% | True |

### hoodie

`Grey Hoodie_Meshy_AI_2026-10-28_c679f7.blend`
SHA-256 `c475adde759716be09d46289e79f6a2a70a7774a1244b605c36affbba7e594c5`

| Budget | Actual vertices / triangles | Skin RMS / p95 / max mm | Min skin silhouette IoU | Pass |
|---:|---:|---:|---:|---|
| 3000 | 3127 / 5799 | 0.372 / 0.737 / 2.517 | 99.779% | False |
| 4500 | 4604 / 8700 | 0.244 / 0.476 / 2.015 | 99.876% | False |
| 6000 | 6077 / 11600 | 0.169 / 0.336 / 2.155 | 99.917% | True |

### dress_pants

`Gray Dress Pants Front and Back_Meshy_AI_2026-10-28_ac302b.blend`
SHA-256 `947efac90bb15d350690002cd20f83f65fb31e5b2b76c225c6adfc0ba6f484fd`

| Budget | Actual vertices / triangles | Skin RMS / p95 / max mm | Min skin silhouette IoU | Pass |
|---:|---:|---:|---:|---|
| 3000 | 3253 / 5534 | 0.206 / 0.412 / 1.145 | 99.850% | False |
| 4500 | 4725 / 8310 | 0.127 / 0.260 / 1.062 | 99.921% | True |
| 6000 | 6165 / 11084 | 0.083 / 0.178 / 1.113 | 99.958% | True |

### jeans

`Blue Jeans on Black_Meshy_AI_2026-10-28_f1bc1c.blend`
SHA-256 `fa012d069810351fd69a41938bb1ca5e0cbd8577d2ec1e4cd3f82df2dd3cd442`

| Budget | Actual vertices / triangles | Skin RMS / p95 / max mm | Min skin silhouette IoU | Pass |
|---:|---:|---:|---:|---|
| 3000 | 3212 / 5812 | 0.313 / 0.636 / 3.144 | 99.745% | False |
| 4500 | 4715 / 8720 | 0.211 / 0.417 / 1.283 | 99.829% | True |
| 6000 | 6201 / 11628 | 0.157 / 0.308 / 1.123 | 99.881% | True |

### bomber

`Olive Bomber Jacket_Meshy_AI_2026-10-28_fd0508.blend`
SHA-256 `6f593e06d8813e8a32fbc88047168ffd9f8450da04700d5bc865b26158b32a07`

| Budget | Actual vertices / triangles | Skin RMS / p95 / max mm | Min skin silhouette IoU | Pass |
|---:|---:|---:|---:|---|
| 3000 | 3128 / 5707 | 0.463 / 0.941 / 3.500 | 99.780% | False |
| 4500 | 4598 / 8563 | 0.265 / 0.564 / 1.856 | 99.865% | False |
| 6000 | 6050 / 11420 | 0.143 / 0.327 / 1.856 | 99.948% | True |

### sneakers

`White Sneakers on Black Background_Meshy_AI_2026-10-28_4c0a02.blend`
SHA-256 `10f0394110190e2e743a7bf32a1dce2d8aba8f9a99a8ea1f4607e79726023f9e`

| Budget | Actual vertices / triangles | Skin RMS / p95 / max mm | Min skin silhouette IoU | Pass |
|---:|---:|---:|---:|---|
| 3000 | 3606 / 5895 | 0.269 / 0.580 / 1.625 | 98.815% | False |
| 4500 | 5045 / 8850 | 0.159 / 0.338 / 1.334 | 99.376% | False |
| 6000 | 6490 / 11804 | 0.112 / 0.235 / 1.002 | 99.628% | True |
