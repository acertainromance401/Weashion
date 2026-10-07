# ClothPhysics

Local C bridge using Bullet Physics 3.25's convex hull construction, used for
WEASHION's static garment preview. Upstream source is unmodified and retained
under `src`.

Source: https://github.com/bulletphysics/bullet3/releases/tag/3.25
Archive: https://codeload.github.com/bulletphysics/bullet3/tar.gz/refs/tags/3.25
License: see LICENSE.txt and the original notices in the source files.

Only LinearMath and BulletCollision are included and compiled. The unused
dynamics and soft-body modules and upstream build files have been removed.
No runtime network access, external service, or downloaded executable is used.
The active bridge does not create a dynamics world, soft body, sparse SDF or
self-collision clusters. Body collision uses convex bands sampled from the
rendered mannequin.

The reusable API separates `weashion_cloth_create_body` from
`weashion_cloth_set_garment`. Clear a completed or cancelled garment with
`weashion_cloth_clear_garment`; destroy the context when the body changes.
Contexts must only be accessed serially.

`weashion_cloth_set_garment` takes both original mesh positions and fitted starting
positions. Edge lengths and strain retain the original reference; displacement
smoothing uses the fitted shape so the collision pass preserves regional fitting.

`weashion_cloth_step` now performs bounded static correction, not time steps.
Each pass spreads displacement to neighboring vertices, weakly restores stretched
edge lengths and projects body intersections outward. Hull planes are computed
once per body and offset by the 2 mm body margin plus 4 mm garment clearance.
Plane offsets conservatively approximate the previous rounded hull margin near
corners; this is not an exact signed-distance query.
Triangle edge midpoints and centroids are sampled in addition to vertices.
128 height buckets restrict the body bands visited by each query. Face bounds
are checked before sampling; unchanged vertices skip the second projection.
Repeated GJK/EPA and ray queries are replaced with plane dot products and a
horizontal exit-distance calculation. The original sample points and maximum
iteration count are retained.
Projection moves horizontally away from the intersected body's band center,
not along the garment normal or toward the artificial caps between body bands.
Each pass also restores part of the displacement toward the fitted shape.
Reference mesh normals are only a fallback when a point is on the band axis.
The pass limit is 12,
with early completion when movement falls below 0.5 mm.

A step returns -1 for cancellation, 0 for invalid state, 1 when another pass is needed, or 2 when the
bounded correction is finished. Completion does not guarantee zero intersection.
The cancellation callback is checked every 128 elements in correction and final
overlap loops. It must not mutate or reenter the context. Body/garment preparation
is still synchronous; the app checks cancellation around those stages.
`weashion_cloth_remaining_overlap` reports the maximum sampled correction still
needed after completion. Unsampled triangle regions and garment self-intersection
are not covered. Excessive edge extension or remaining overlap produces a warning
in the app without hiding an otherwise renderable garment.

The C API does not accept fabric settings. The app catalog retains only the
strain limit as a visual correction warning threshold, not a calibrated value.
This is not a physical fit prediction. No device performance or visual quality
measurements are claimed.