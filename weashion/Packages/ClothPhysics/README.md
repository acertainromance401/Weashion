# ClothPhysics

Local C bridge using Bullet Physics 3.25's vector math for WEASHION's static
garment preview. Upstream source is unmodified and retained under `src`.

Source: https://github.com/bulletphysics/bullet3/releases/tag/3.25
Archive: https://codeload.github.com/bulletphysics/bullet3/tar.gz/refs/tags/3.25
License: see LICENSE.txt and the original notices in the source files.

Only LinearMath and BulletCollision are included and compiled. The unused
dynamics and soft-body modules and upstream build files have been removed.
No runtime network access, external service, or downloaded executable is used.
The active bridge does not create a dynamics world, soft body, sparse SDF or
self-collision clusters. Body collision uses triangles from the rendered
mannequin and already-settled inner garment panels, indexed by median-split
triangle BVHs. Each surface has its own tree so a nearer skin triangle cannot
hide penetration into an inner garment.

The reusable API separates `weashion_cloth_create_body` from
`weashion_cloth_set_garment`. Clear a completed or cancelled garment with
`weashion_cloth_clear_garment`; destroy the context when the body changes.
Contexts must only be accessed serially.

`weashion_cloth_create_layered_body` accepts a surface-group byte per triangle:
0 for the body and 1–3 for inner layers. A valid group-0 body is required; values
above 3 are rejected. The original `weashion_cloth_create_body` API remains a
single-surface wrapper. Body contact retains nearest-triangle projection.
Inner layers instead use two-sided ray intersections with finite panels along
an anatomical outward direction, taking the outermost local intersection in
each layer. This prevents a reversed lining or an open hem's infinite plane
from pulling an outer garment into the wearer. Folded panels remain present,
and their winding does not determine the push direction. Layered sleeves can
use a radial guide around their local arm centerline; torso samples use a
vertical torso-center guide. The radial direction is recomputed from the
current sample position. Unguided shoulder samples retain the nearest-skin
fallback. If an outward layer correction would enter nearby skin, it slides
along the skin tangent instead; an already-inside sample first projects out of
skin. The reported depth is not reduced by this direction constraint.
The trees remain
independent so skin cannot mask an inner layer. Contact corrects the deepest
sampled violation. This is a body-normal envelope approximation, not complete
cloth-to-cloth contact or dynamics. The app supplies original panel triangles,
not decorative bindings or
curved display subdivisions.

`weashion_cloth_set_garment` takes both original mesh positions and fitted starting
positions. Edge and bending distances retain the original reference. Geodesic
tethers bound displacement relative to the upper garment region.

After preparation, `weashion_cloth_pin_vertices` can fix validated vertex indices
at their fitted starting positions. A call validates the complete index list
before changing masses; it returns 0 on invalid input and 1 on success. Pins
are cleared with the garment. The app's regular cloth mode uses ordered cuff rims only when a
measured long sleeve extends past the wrist but its opening is narrower than
the actual hand envelope. Distal placement is compressed toward the wrist;
the original product/rest mesh is retained, allowing excess sleeve length to
fold instead of being forced through the hand. This is a static cuff-stop
approximation, not a clasp, sliding constraint or dynamic hand-dressing model.
An opening smaller than the wrist can still intersect skin and must warn.
Shape-preserving hoodies retain initial wrist-stop placement but allow bounded
contact adjustment of the cuffs rather than pinning their rims.

`weashion_cloth_project_shape` is an alternative to `weashion_cloth_step`, not
an additional settling stage. It preserves the fitted starting shape and runs
only bounded contact correction plus local edge-shape safeguards; it does not
apply gravity, source-pose bending constraints, geodesic tethers or the 96-pass
cleanup. The caller supplies one finite displacement radius (0–40 mm) per
vertex and 1–16 passes. Zero-radius vertices and existing pins stay at their
fitted positions. Validation completes before changing masses. The app's
hoodie policy fixes the hood body, not the entire neck/back transition. Its
geometric support weight fades toward the neck opening and shoulders; the
hood is placed 20 mm backward before projection. The radius smoothly increases
toward the body/sleeves (at most 40 mm), using at most twelve contact passes.
Contact movement is capped at 4 mm per pass (layer contacts retain their 2 mm
cap). Six local sweeps target a 10% band around fitted edge lengths and a 2%
band across fitted neighboring triangles, not source-pose bending. Sixteen
neighbor-averaging sweeps smooth each contact increment, not the original
garment positions or accumulated displacement. Local backtracking prevents
face inversion/collapse and new obtuse folds across initially non-obtuse
fitted hinges, with at most 24 backtracking sweeps per contact pass. A face
retains at least 10% of its fitted area and a normal within 60 degrees of its
fitted normal. The final guard is checked explicitly; an unsafe result fails
rather than being returned as a successful fit. Radius limits and geometric
safeguards take precedence over edge bands and contact clearance; this is
not a strict edge-length or collision guarantee.
Fully fixed faces skip contact correction, but all vertices and seven samples
per triangle remain included in the final reported overlap. The app also
measures the displayed body overlap as usual. Fixed hood geometry, tight cuffs
or sleeves passing over the hands, and constrained neighboring faces can retain
skin penetration; shape preservation does not assert clearance there.
A result returns 2, invalid input or an unsafe correction returns 0, and
cancellation returns -1. Clear the garment before starting a
different solve mode. This is a visual fit policy, not calibrated cloth physics.

`weashion_cloth_step` now performs bounded static correction, not time steps.
Each pass applies a small settling displacement, bending and edge constraints,
tethers, nearest-triangle contact projection and tangential contact friction.
Contact uses a 4 mm garment clearance. BVH queries retain the original local
3 cm cell-neighborhood search domain; this is not a global signed-distance or
continuous collision query. Layer intersections are clipped to that neighborhood
and at most 12 cm outward. A global body query is used only to obtain a reference
direction if no local skin triangle is present, not to apply distant contact.
Per-sample triangle hints initialize an exact query bound; every potentially
closer body node or farther intersecting layer node is still checked. Hints clear
when the garment is cleared/reprepared.
Seven barycentric samples per triangle cover its centroid, edge midpoints and
the centroids of the four subdivided display triangles. The main pass limit is
72, with early completion after nine passes when movement is below 1 mm.
Up to 96 final contact passes alternate with four forward/reverse edge-extension
projections, attempting sampled skin penetration below 1 mm without unbounded
contact-only stretching. Residual scans are batched after every four final
contact passes, with a final scan before completion; contact samples, extension
projections and the 96-pass cap are not reduced. Fully pinned vertices and face
samples do not drive additional passes, but their penetration remains in the
reported residual. Correction also stops after two consecutive four-pass batches
with less than 0.05 mm maximum displacement and 0.05 mm change in movable-sample
penetration. This avoids repeating stationary, infeasible contacts without
claiming they have been resolved. `weashion_cloth_final_contact_passes` exposes
the number of final contact passes for diagnostics and resets with the garment.
For layered contexts, each individual contact projection is limited to 2 mm to
avoid large, conflicting triangle corrections. Three consecutive four-pass
batches without a 0.1% improvement in the best squared movable-penetration sum
stop oscillating correction; the lowest-energy sampled state is restored.
Layered completion then gives edge-extension constraints up to 64 additional
four-sweep batches (0.1 mm movable-edge excess target). Since this projection
can pull cloth back into skin, up to 16 additional skin-only contact passes
follow, stopping when movable sampled skin depth is at most 1 mm. Pinned
penetration remains reported. These bounded 2 mm projections do not push
against inner clothes again and can increase measured edge extension; the
app must retain stretch warnings rather than presenting a physically feasible
fit. The final-contact diagnostic count includes these passes (at most 112).
The full skin/layer residual is measured again afterward; unresolved
cloth-to-cloth penetration is not turned into a zero-overlap success.
The constraints are iterative, not a proof of feasibility or a strict final
material bound. Remaining penetration and measured
edge extension must still be inspected, including the displayed smoothed
surface. Zero sampled penetration is not sufficient visual validation.

The app also checks the actual curved display mesh against the body. A
point-normal edge midpoint falls back to its linear midpoint only when that
reduces measured skin penetration; original vertices, product dimensions and
topology are not changed by this display-only safeguard.
`weashion_cloth_body_depth` samples a point against group 0 and returns NaN for
invalid inputs. `weashion_cloth_measure_body_overlap` checks all supplied
vertices and seven samples per supplied display triangle, returning 1 on
success, 0 for invalid input, or -1 for cancellation. Its output is written
only on success. These queries share the local-neighborhood limitation and do
not certify complete intersection freedom. The app combines the display-body
residual with the solver residual when reporting overlap. Rigid shoes now also
report sampled display-body penetration, but are not deformed to resolve it;
this is not a shoe-interior or comfort test.

A step returns -1 for cancellation, 0 for invalid state, 1 when another pass is needed, or 2 when the
bounded correction is finished. Completion does not guarantee zero intersection.
The cancellation callback is checked every 128 elements in correction and final
overlap loops. It must not mutate or reenter the context. Body/garment preparation
is still synchronous; the app checks cancellation around those stages.
`weashion_cloth_remaining_overlap` reports maximum sampled depth below any
collision surface under these body-normal/nearest-point queries, including pinned
samples and excluding clearance. Contacts missed by the reference direction,
unsampled triangle regions and garment self-intersection
are not covered. `weashion_cloth_max_strain` reports the largest positive relative
extension among reference edges at least 5 mm long, not a percentile or a
calibrated textile strain. Excessive extension or remaining overlap produces a
warning in the app.

`weashion_cloth_configure` accepts per-vertex extension estimates, bending
compliance, surface density and torso-only arm-exclusion flags. The flag byte
combines `WEASHION_CLOTH_EXCLUDE_BODY_ARMS` (1) and
`WEASHION_CLOTH_EXCLUDE_LAYER_ARMS` (2) and
`WEASHION_CLOTH_LAYER_ARMS_ONLY` (4); other bits and simultaneous layer
exclusion/arms-only selection are rejected. The layer exclusion flag
uses a torso-only reference normal and omits inner sleeve panels, without
disabling required skin-arm contact. The app no longer excludes body arms on
legacy short-sleeve shirts either: the old exclusion concealed 16–22 mm of
male arm penetration from solver-only diagnostics. The exclusion API remains
available for compatibility and explicit synthetic tests. Inner
panels are classified from the source sleeve bindings. For a face sample, only
corners with nonzero barycentric weight contribute to its exclusion mask.
BVH nodes store whether they contain arm/torso triangles, allowing exact
filtered subtree pruning. Ray slab reciprocals are computed once per query;
the finite triangle tests and contact sample counts are not reduced.

`weashion_cloth_set_contact_guides` takes one origin and axis per original
garment vertex. Zero axes disable guidance; other axes must be finite unit
vectors (squared-length tolerance 0.001). All inputs are validated before
replacing guides. Face guides interpolate contributing corners only when all
are guided. Guides clear with the garment and are used for layer direction,
not to disable skin collision or resize the product.

These settings
are estimates, not measured material data. This is not a physical fit prediction.
No device performance or visual quality measurements are claimed.