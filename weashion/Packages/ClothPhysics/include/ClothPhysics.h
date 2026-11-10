#ifndef WEASHION_CLOTH_PHYSICS_H
#define WEASHION_CLOTH_PHYSICS_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct WeashionCloth WeashionCloth;
typedef int32_t (*WeashionClothCancellationCheck)(void);

#define WEASHION_CLOTH_EXCLUDE_BODY_ARMS 1u
#define WEASHION_CLOTH_EXCLUDE_LAYER_ARMS 2u
#define WEASHION_CLOTH_LAYER_ARMS_ONLY 4u

WeashionCloth *weashion_cloth_create_body(
    const float *vertices, int32_t vertexCount, const int32_t *indices, int32_t triangleCount,
    const uint8_t *armTriangles);
WeashionCloth *weashion_cloth_create_layered_body(
    const float *vertices, int32_t vertexCount, const int32_t *indices, int32_t triangleCount,
    const uint8_t *armTriangles, const uint8_t *surfaceGroups);
int32_t weashion_cloth_set_garment(
    WeashionCloth *cloth, const float *positions, int32_t vertexCount,
    const int32_t *triangles, int32_t triangleCount, const float *fittedPositions);
int32_t weashion_cloth_configure(
    WeashionCloth *cloth, const uint8_t *torsoOnly, const float *extensionLimits,
    int32_t vertexCount, float bendingCompliance, float surfaceDensity);
int32_t weashion_cloth_set_contact_guides(
    WeashionCloth *cloth, const float *origins, const float *axes, int32_t vertexCount);
int32_t weashion_cloth_pin_vertices(WeashionCloth *cloth, const int32_t *indices, int32_t count);
void weashion_cloth_clear_garment(WeashionCloth *cloth);

int32_t weashion_cloth_step(WeashionCloth *cloth, int32_t steps, WeashionClothCancellationCheck isCancelled);
int32_t weashion_cloth_project_shape(
    WeashionCloth *cloth, const float *maximumDisplacements, int32_t vertexCount,
    int32_t passes, WeashionClothCancellationCheck isCancelled);
void weashion_cloth_copy_positions(const WeashionCloth *cloth, float *positions);
float weashion_cloth_max_strain(const WeashionCloth *cloth);
float weashion_cloth_remaining_overlap(const WeashionCloth *cloth);
int32_t weashion_cloth_final_contact_passes(const WeashionCloth *cloth);
float weashion_cloth_body_depth(WeashionCloth *cloth, const float *position);
int32_t weashion_cloth_measure_body_overlap(
    WeashionCloth *cloth, const float *positions, int32_t vertexCount,
    const int32_t *indices, int32_t triangleCount, float *overlap,
    WeashionClothCancellationCheck isCancelled);
void weashion_cloth_destroy(WeashionCloth *cloth);

#ifdef __cplusplus
}
#endif

#endif