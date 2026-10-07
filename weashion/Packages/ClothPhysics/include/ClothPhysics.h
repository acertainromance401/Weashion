#ifndef WEASHION_CLOTH_PHYSICS_H
#define WEASHION_CLOTH_PHYSICS_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct WeashionCloth WeashionCloth;
typedef int32_t (*WeashionClothCancellationCheck)(void);

WeashionCloth *weashion_cloth_create_body(
    const float *bodyPoints, const int32_t *bandCounts, int32_t bandCount);
int32_t weashion_cloth_set_garment(
    WeashionCloth *cloth, const float *positions, int32_t vertexCount,
    const int32_t *triangles, int32_t triangleCount, const float *fittedPositions);
void weashion_cloth_clear_garment(WeashionCloth *cloth);

int32_t weashion_cloth_step(WeashionCloth *cloth, int32_t steps, WeashionClothCancellationCheck isCancelled);
void weashion_cloth_copy_positions(const WeashionCloth *cloth, float *positions);
float weashion_cloth_max_strain(const WeashionCloth *cloth);
float weashion_cloth_remaining_overlap(const WeashionCloth *cloth);
void weashion_cloth_destroy(WeashionCloth *cloth);

#ifdef __cplusplus
}
#endif

#endif