# Upper sleeve source-binding diagnostic — read-only

## Result

**The shoulder→cuff chord is not the source sleeve centerline.** This is an actual binding defect, not merely insufficient collision clearance. For the long sleeve and bomber, that chord is **outside** several measured proximal/mid-sleeve lumen sections. It places genuine front-surface vertices nearly on the arm axis or on its back side before collision. Opposite-side point projection can then open large triangular spikes even with submillimetre final point overlap.

At the diagnostic snapshot, no runtime JSON, optimized Blend, source original, Swift or catalog was edited. Resource and Blend SHA-256 values matched the previous independent validation reports. The diagnostic only created its script, JSON and this report in the conversion folder. Subsequent publication added dedicated sleeve metadata to derived JSON/Blend files; see [the conversion report](conversion_report.md). The measured source geometry below was not replaced.

## Method and scope

`python3 weashion/reference/garments/diagnose_upper_sleeves.py`

The script intersects the **published normalized source-derived skins**, not a generic cylinder, with 12 X-constant planes per garment. Ordered closed intersection components provide polygon-area centroids, actual folded perimeter and interpolated sleeve weights. Neighbouring centers estimate tangents; second intersections perpendicular to those tangents provide the reported near-normal sections. Submillimetre numerical cleanup is already included. No Desktop reload, original redecimation, native fit rerun or full-source silhouette rerun is involved.

Centers are polygon-area centroids, **not vertex-density averages**. “Axis outside” tests the assumed chord's intersection with that section's actual polygon. Circumferences include source folds; they are not artificially enlarged to prevent collision.

Proximal sections include cap/axilla fullness, especially the hoodie. These are geometric lumen/contour centers, **not measured bone-joint locations**. The sources have no rig or reliable anatomical elbow marker; “mid-sleeve” must not be relabeled as an exact elbow joint. A single tangent-refinement pass is a bounded diagnostic, not final reviewed anatomical authoring.

## Measurements

Metres, +Y up, +Z front. Error is shortest distance from measured center to the existing shoulder→cuff chord.

| Garment / region | Measured center [X,Y,Z] | Actual section circumference | Chord error | Chord inside section? |
|---|---|---:|---:|---|
| Long / proximal cap | [.24192, -.13558, -.03822] | .52283 | 98.8 mm | No |
| Long / upper sleeve | [.31069, -.17384, -.04017] | .48196 | 85.0 mm | No |
| Long / upper-mid | [.38239, -.21032, -.02557] | .37195 | 60.9 mm | No |
| Long / mid | [.45610, -.25566, -.01464] | .31523 | 45.6 mm | No |
| Hoodie / broad proximal cap | [.27173, -.18610, -.03202] | .88074 | 85.6 mm | Yes |
| Hoodie / cap-to-sleeve | [.32269, -.29353, -.02977] | .69032 | 92.1 mm | Yes |
| Hoodie / upper-mid | [.37581, -.33857, -.02668] | .56169 | 67.4 mm | Yes |
| Hoodie / mid-distal | [.44052, -.38781, -.02339] | .40492 | 35.1 mm | Yes |
| Bomber / proximal cap | [.28417, -.19142, -.04428] | .58573 | 106.3 mm | No |
| Bomber / upper sleeve | [.31780, -.21700, -.04240] | .5541 | 97.7 mm | No |
| Bomber / upper-mid | [.41250, -.28675, -.02965] | .44142 | 70.1 mm | No |
| Bomber / mid | [.47669, -.33858, -.01569] | .38632 | 51.5 mm | No |

The hoodie chord is also badly off-center, but its broad dropped cap encloses it. That is consistent with the hoodie fitting better; it does **not** make its chord a correct centerline.

The source upper sleeves sit rearward (negative Z), then curve toward the cuff's positive Z in the long sleeve/bomber. Lowering a single root in Y or adding a fixed Z offset cannot reproduce the changing offsets. Keep Y0/hem/reference-length conventions unchanged. The current shoulder values are sample **measurement/attachment anchors**, not validated sleeve-axis centers.

Right/left X-section center asymmetry is small but real: sampled maxima approximately 5.82 mm long, 1.27 mm hoodie, 1.12 mm bomber. A production binding should measure each side, rather than impose perfect symmetry.

## Exact supplied triangle and cap-weight evidence

Current long-sleeve triangle **4991 is exactly [2587,2645,2630]**, with sleeve blend weights [.968066,1,1].

| Vertex | Existing chord radius | Radius about measured section | Existing radial Z | Z relative to measured section center |
|---|---:|---:|---:|---:|
| 2587 | 29.12 mm | 72.52 mm | +4.53 mm | +56.30 mm |
| 2645 | 32.15 mm | 61.77 mm | +8.69 mm | +59.27 mm |
| 2630 | 18.50 mm | 64.84 mm | **−1.82 mm** | **+46.33 mm** |

The provided front triangle is almost wholly sleeve-bound; its near-axis initialization is therefore **not explained by a weight transition within that triangle**. Vertex2630 is a particularly useful front/back-sign regression.

Vertex2525 (blend0) and2587 (blend.968066) lie only **.338 mm apart longitudinally** relative to the same measured section plane: signed plane distances −10.059 and −9.721 mm. Their physical sleeve radii are approximately76.44 and72.52 mm. At this section, the interpolated blend spans0…1: upper-half mean.971, lower-half mean.360;13.9% of perimeter is below.1 and45.5% above.9.

Existing generation uses global `abs(X)` thresholds multiplied by a Y gate relative to the erroneous straight axis. It is not a mesh armhole/cap parameterization. On right-sleeve edges the blend jumps by more than.5 on22 long,68 hoodie and39 bomber edges. Edge lengths/examples are retained in JSON; these counts do not by themselves prove every jump is wrong.

**Do not simply change2525 to1 or force every proximal ring to one weight.** Medial axilla/cap vertices can legitimately remain torso-bound while the outer cap follows the arm. That anatomy must be authored separately from a tube's axial coordinate; the present `sleeveProgress` conflates their interpretation. Distal closed tube sections should have consistent arm binding, without an arbitrary upper/lower split.

## Concrete retargeting contract

`upper_sleeve_diagnostic.json` includes measured sections, source weights, supplied face/vertices, hashes and **13 long /13 hoodie /12 bomber candidate centerline knots**. Each knot has:

```
center, tangent, radialAxis, depthAxis,
legacyAxialCoordinate, arcFromFirstMeasuredSection,
circumference, role
```

The last knot is the existing ordered cuff-loop mean; its circumference is the existing sizing reference. Other knots are measured cap/tube sections, not anatomically labeled joints. Frames begin with +Z projected perpendicular to the source tangent and are then parallel-transported by minimal tangent rotations. No abrupt front/back frame sign changes are permitted.

Suggested implementation:

1. **Keep measurement anchors separate.** Do not replace `sizing.rightShoulder` with a lowered lumen center: torso attachment, shoulder sizing and reference length depend on its existing meaning. Add a dedicated source-sleeve binding.
2. **Author independent coordinates.** Per vertex, store a source station plus signed local radial coordinates and a distinct `armBlend`. Obtain the station by local projection onto a smooth, monotonic interpolated measured centerline, not by projection onto shoulder→cuff. Store a tangent residual if closest-segment projection is used; do not throw away cloth folds.
3. **Map full sections coherently.** For source `p = C(u)+R(u)*r+D(u)*d` and matched body/garment centerline frame `B(u),Rb(u),Db(u)`, initialize `pArm=B(u)+Rb(u)*r+Db(u)*d`. Transport source and destination frames continuously. Do not normalize these radii to body girth; preserve the source's actual sleeve ease and relief.
4. **Preserve current axial placement for a bounded first integration.** JSON supplies monotonic `legacyAxialCoordinate = dot(C−measurementShoulder, oldChordDirection)`. It ranges from approximately.1011 to.6101 m for long and.1687 to.6201 m for bomber; the cuff endpoint exactly retains the existing reference chord length. This lets the current body-chain `frame(at:)` use section-center distances while replacing the incorrect radial origin and frame. Unlike current per-point chord projection, all points of a transverse section share that axial station. Later anatomical root/elbow correspondence can replace this scalar mapping after explicit authoring.
5. **Handle cap as cap, not cylinder.** Torso/neck/hood seed vertices retain torso attachment; a reviewed distal sleeve ring is the arm-bound seed. Blend continuously across the actual connected cap/armhole patch using mesh-geodesic/harmonic weights (or reviewed seam correspondences), not global X/Y gates. Constrain weights only inside that cap region; require armBlend1 in the separated tube. Do not extrapolate the first measured cap centerline indefinitely into the torso. Hoodie broad-cap fullness remains intentionally non-tubular.
6. **Resize the binding with the garment.** Source centerline, station mapping and local radial coordinates must be transformed consistently during S/M/L/custom resizing. Updating shoulder/cuff only while leaving source centerline coordinates stale reintroduces the error. Preserve distal opening taper and original measured sleeve ease; no fake girth enlargement.
7. **Collision remains sided and secondary.** Once signed source-front depth is correct, preserve that sector during body contact. Closest-point projection alone can still choose the wrong side of an arm/torso or flip a whole face. Check face orientation/normal consistency, not only vertex overlap. This diagnostic does not claim that centerline correction alone guarantees solver stability.

Recommended regressions before publishing any binding change: supplied face4991 retains positive source-front depth for all three vertices; section radius does not collapse toward zero; cap deformation is continuous across neighbouring faces; full tube sections remain coherently parameterized; cuff, hood, silhouette, authored triangle margin and all existing native sizing tests stay valid.

The centerline knots are **diagnostic candidates**, not permission to change current exports or a claim that a new native fit has been validated.
