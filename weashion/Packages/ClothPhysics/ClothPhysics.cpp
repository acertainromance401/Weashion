#include "ClothPhysics.h"
#include "LinearMath/btVector3.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <functional>
#include <memory>
#include <queue>
#include <unordered_map>
#include <vector>

static uint64_t edgeKey(int first, int second) {
    return (uint64_t(std::min(first, second)) << 32) | uint32_t(std::max(first, second));
}

static bool finiteVector(const btVector3& value) {
    return std::isfinite(value.x()) && std::isfinite(value.y()) && std::isfinite(value.z());
}

static bool cancelled(WeashionClothCancellationCheck check, size_t progress) {
    return progress % 128 == 0 && check && check() != 0;
}

struct GarmentEdge {
    int first;
    int second;
    btScalar restLength;
    int opposite = -1;
};

static const std::array<btVector3, 7> faceSamples = {
    btVector3(1.0f / 3, 1.0f / 3, 1.0f / 3),
    btVector3(0.5f, 0.5f, 0), btVector3(0, 0.5f, 0.5f), btVector3(0.5f, 0, 0.5f),
    btVector3(2.0f / 3, 1.0f / 6, 1.0f / 6),
    btVector3(1.0f / 6, 2.0f / 3, 1.0f / 6),
    btVector3(1.0f / 6, 1.0f / 6, 2.0f / 3)
};

static btVector3 directionOr(const btVector3& direction, const btVector3& fallback) {
    return finiteVector(direction) && !direction.fuzzyZero() ? direction.normalized() : fallback;
}

struct BodyTriangle {
    btVector3 a;
    btVector3 b;
    btVector3 c;
    btVector3 normal;
    bool arm;
    uint8_t group;
    btVector3 minimum;
    btVector3 maximum;
};

static btScalar boundsDistanceSquared(const btVector3& point, const btVector3& minimum, const btVector3& maximum) {
    btScalar distance = 0;
    for (int axis = 0; axis < 3; ++axis) {
        const btScalar delta = btMax(minimum[axis] - point[axis],
                                    btMax(point[axis] - maximum[axis], btScalar(0)));
        distance += delta * delta;
    }
    return distance;
}

static btVector3 closestPoint(const btVector3& point, const BodyTriangle& triangle) {
    const btVector3 ab = triangle.b - triangle.a;
    const btVector3 ac = triangle.c - triangle.a;
    const btVector3 ap = point - triangle.a;
    const btScalar d1 = ab.dot(ap);
    const btScalar d2 = ac.dot(ap);
    if (d1 <= 0 && d2 <= 0) return triangle.a;
    const btVector3 bp = point - triangle.b;
    const btScalar d3 = ab.dot(bp);
    const btScalar d4 = ac.dot(bp);
    if (d3 >= 0 && d4 <= d3) return triangle.b;
    const btScalar vc = d1 * d4 - d3 * d2;
    if (vc <= 0 && d1 >= 0 && d3 <= 0) return triangle.a + ab * (d1 / (d1 - d3));
    const btVector3 cp = point - triangle.c;
    const btScalar d5 = ab.dot(cp);
    const btScalar d6 = ac.dot(cp);
    if (d6 >= 0 && d5 <= d6) return triangle.c;
    const btScalar vb = d5 * d2 - d1 * d6;
    if (vb <= 0 && d2 >= 0 && d6 <= 0) return triangle.a + ac * (d2 / (d2 - d6));
    const btScalar va = d3 * d6 - d5 * d4;
    if (va <= 0 && d4 - d3 >= 0 && d5 - d6 >= 0) {
        return triangle.b + (triangle.c - triangle.b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)));
    }
    const btScalar denominator = 1 / (va + vb + vc);
    return triangle.a + ab * (vb * denominator) + ac * (vc * denominator);
}

struct WeashionCloth {
    static constexpr btScalar cellSize = 0.03f;
    static constexpr btScalar clearance = 0.004f;
    static constexpr btScalar layerContactStep = 0.002f;
    std::vector<BodyTriangle> triangles;
    btVector3 gridMinimum;
    int gridSize[3] = {0, 0, 0};
    struct SurfaceNode {
        btVector3 minimum;
        btVector3 maximum;
        uint32_t begin;
        uint32_t end;
        int left = -1;
        int right = -1;
        bool hasArms = false;
        bool hasTorso = false;
    };
    std::vector<SurfaceNode> surfaceNodes;
    std::vector<uint32_t> surfaceOrder;
    std::vector<int> surfaceHints;
    std::array<int, 4> surfaceRoots = {-1, -1, -1, -1};
    int surfaceGroupCount = 1;
    std::vector<btVector3> restPositions;
    std::vector<btVector3> fitPositions;
    std::vector<btVector3> positions;
    std::vector<btVector3> directions;
    std::vector<btVector3> contactOrigins;
    std::vector<btVector3> contactAxes;
    std::vector<std::array<int, 3>> faces;
    std::vector<GarmentEdge> edges;
    std::vector<GarmentEdge> bends;
    std::vector<GarmentEdge> tethers;
    std::vector<btScalar> edgeLambdas;
    std::vector<btScalar> bendLambdas;
    std::vector<btScalar> vertexAreas;
    std::vector<btScalar> inverseMasses;
    // Below the armpit, body panels sit between arm and torso instead of wrapping around the arm.
    std::vector<uint8_t> torsoOnly;
    std::vector<btVector3> corrections;
    std::vector<int> correctionCounts;
    std::vector<btScalar> extensionLimits;
    btScalar bendingCompliance = 4;
    btScalar gravityStep = 0.0015f;
    btScalar meanArea = 0;
    int completedSteps = 0;
    btScalar remainingOverlap = 0;
    btScalar remainingMovableOverlap = 0;
    btScalar movableOverlapEnergy = 0;
    int finalContactPasses = 0;

    int cellCoordinate(btScalar value, int axis) const {
        return int(std::floor((value - gridMinimum[axis]) / cellSize));
    }

    int buildSurfaceNode(uint32_t begin, uint32_t end) {
        SurfaceNode node{triangles[surfaceOrder[begin]].minimum, triangles[surfaceOrder[begin]].maximum, begin, end};
        for (uint32_t slot = begin + 1; slot < end; ++slot) {
            node.minimum.setMin(triangles[surfaceOrder[slot]].minimum);
            node.maximum.setMax(triangles[surfaceOrder[slot]].maximum);
        }
        for (uint32_t slot = begin; slot < end; ++slot) {
            const bool arm = triangles[surfaceOrder[slot]].arm;
            node.hasArms = node.hasArms || arm;
            node.hasTorso = node.hasTorso || !arm;
        }
        const int index = int(surfaceNodes.size());
        surfaceNodes.push_back(node);
        if (end - begin > 8) {
            const int axis = (node.maximum - node.minimum).maxAxis();
            const uint32_t middle = begin + (end - begin) / 2;
            std::nth_element(surfaceOrder.begin() + begin, surfaceOrder.begin() + middle, surfaceOrder.begin() + end,
                             [&](uint32_t a, uint32_t b) {
                return triangles[a].minimum[axis] + triangles[a].maximum[axis]
                    < triangles[b].minimum[axis] + triangles[b].maximum[axis];
            });
            const int left = buildSurfaceNode(begin, middle);
            const int right = buildSurfaceNode(middle, end);
            surfaceNodes[index].left = left;
            surfaceNodes[index].right = right;
        }
        return index;
    }

    void indexBody() {
        btVector3 maximum = triangles.front().a;
        gridMinimum = maximum;
        for (const auto& triangle : triangles) {
            for (const auto& corner : {triangle.a, triangle.b, triangle.c}) {
                gridMinimum.setMin(corner);
                maximum.setMax(corner);
            }
        }
        gridMinimum -= btVector3(cellSize, cellSize, cellSize);
        maximum += btVector3(cellSize, cellSize, cellSize);
        for (int axis = 0; axis < 3; ++axis) {
            gridSize[axis] = std::max(1, int(std::ceil((maximum[axis] - gridMinimum[axis]) / cellSize)));
        }
        surfaceOrder.resize(triangles.size());
        for (uint32_t index = 0; index < triangles.size(); ++index) surfaceOrder[index] = index;
        std::stable_sort(surfaceOrder.begin(), surfaceOrder.end(), [&](uint32_t a, uint32_t b) {
            return triangles[a].group < triangles[b].group;
        });
        surfaceNodes.reserve(triangles.size() / 2);
        uint32_t begin = 0;
        for (int group = 0; group < surfaceGroupCount; ++group) {
            uint32_t end = begin;
            while (end < surfaceOrder.size() && triangles[surfaceOrder[end]].group == group) ++end;
            if (end > begin) surfaceRoots[group] = buildSurfaceNode(begin, end);
            begin = end;
        }
    }

    // Searches the surrounding cells, so penetrations deeper than one cell are not detected.
    bool nearestSurface(const btVector3& position, bool skipArms, btVector3& point, btVector3& normal,
                        size_t hintIndex, int group, bool localOnly = true, bool onlyArms = false) {
        if (surfaceRoots[group] < 0) return false;
        hintIndex = hintIndex * size_t(surfaceGroupCount) + size_t(group);
        btVector3 searchMinimum, searchMaximum;
        if (localOnly) {
            for (int axis = 0; axis < 3; ++axis) {
                const int center = cellCoordinate(position[axis], axis);
                if (center < 0 || center >= gridSize[axis]) return false;
                searchMinimum[axis] = gridMinimum[axis] + btScalar(center - 1) * cellSize;
                searchMaximum[axis] = gridMinimum[axis] + btScalar(center + 2) * cellSize;
            }
        }
        const auto intersectsNeighborhood = [&](const btVector3& low, const btVector3& high) {
            if (!localOnly) return true;
            for (int axis = 0; axis < 3; ++axis) {
                if (low[axis] >= searchMaximum[axis] || high[axis] < searchMinimum[axis]) return false;
            }
            return true;
        };
        btScalar best = SIMD_INFINITY;
        int bestTriangle = -1;
        const bool cacheHint = hintIndex < surfaceHints.size();
        const int hint = cacheHint ? surfaceHints[hintIndex] : -1;
        if (hint >= 0) {
            const auto& triangle = triangles[hint];
            if ((!skipArms || !triangle.arm) && (!onlyArms || triangle.arm)
                && intersectsNeighborhood(triangle.minimum, triangle.maximum)) {
                point = closestPoint(position, triangle);
                normal = triangle.normal;
                best = (position - point).length2();
                bestTriangle = hint;
            }
        }
        std::array<int, 64> pending;
        int count = 1;
        pending[0] = surfaceRoots[group];
        while (count > 0) {
            const auto& node = surfaceNodes[pending[--count]];
            if ((skipArms && !node.hasTorso) || (onlyArms && !node.hasArms)) continue;
            if (boundsDistanceSquared(position, node.minimum, node.maximum) > best
                || !intersectsNeighborhood(node.minimum, node.maximum)) continue;
            if (node.left >= 0) {
                const auto& left = surfaceNodes[node.left];
                const auto& right = surfaceNodes[node.right];
                const bool leftFirst = boundsDistanceSquared(position, left.minimum, left.maximum)
                    <= boundsDistanceSquared(position, right.minimum, right.maximum);
                // Median splitting and the 400k-face API limit keep depth below 20.
                pending[count++] = leftFirst ? node.right : node.left;
                pending[count++] = leftFirst ? node.left : node.right;
                continue;
            }
            for (uint32_t slot = node.begin; slot < node.end; ++slot) {
                const auto& triangle = triangles[surfaceOrder[slot]];
                if ((skipArms && triangle.arm) || (onlyArms && !triangle.arm)
                    || boundsDistanceSquared(position, triangle.minimum, triangle.maximum) > best
                    || !intersectsNeighborhood(triangle.minimum, triangle.maximum)) continue;
                const btVector3 candidate = closestPoint(position, triangle);
                const btScalar distance = (position - candidate).length2();
                if (distance < best) {
                    best = distance;
                    point = candidate;
                    normal = triangle.normal;
                    bestTriangle = int(surfaceOrder[slot]);
                }
            }
        }
        if (cacheHint) surfaceHints[hintIndex] = bestTriangle;
        return best < SIMD_INFINITY;
    }

    bool outerLayerContact(const btVector3& position, const btVector3& outward, bool skipArms, size_t hintIndex,
                           int group, btScalar& distance, bool onlyArms = false) {
        if (surfaceRoots[group] < 0) return false;
        hintIndex = hintIndex * size_t(surfaceGroupCount) + size_t(group);
        btVector3 searchMinimum, searchMaximum;
        for (int axis = 0; axis < 3; ++axis) {
            const int center = cellCoordinate(position[axis], axis);
            if (center < 0 || center >= gridSize[axis]) return false;
            searchMinimum[axis] = gridMinimum[axis] + btScalar(center - 1) * cellSize;
            searchMaximum[axis] = gridMinimum[axis] + btScalar(center + 2) * cellSize;
        }
        distance = -clearance;
        int bestTriangle = -1;
        btVector3 inverseDirection;
        for (int axis = 0; axis < 3; ++axis) {
            inverseDirection[axis] = btFabs(outward[axis]) < 1e-8f ? 0 : 1 / outward[axis];
        }
        const auto intersectsRay = [&](const btVector3& minimum, const btVector3& maximum) {
            btScalar near = -clearance;
            btScalar far = 0.12f;
            for (int axis = 0; axis < 3; ++axis) {
                const btScalar low = btMax(minimum[axis], searchMinimum[axis]);
                const btScalar high = btMin(maximum[axis], searchMaximum[axis]);
                if (low > high) return false;
                if (btFabs(outward[axis]) < 1e-8f) {
                    if (position[axis] < low || position[axis] > high) return false;
                    continue;
                }
                const btScalar first = (low - position[axis]) * inverseDirection[axis];
                const btScalar second = (high - position[axis]) * inverseDirection[axis];
                near = btMax(near, btMin(first, second));
                far = btMin(far, btMax(first, second));
                if (near > far) return false;
            }
            return far >= distance;
        };
        const auto testTriangle = [&](int index) {
            const auto& triangle = triangles[index];
            if ((skipArms && triangle.arm) || (onlyArms && !triangle.arm)) return;
            if (!intersectsRay(triangle.minimum, triangle.maximum)) return;
            const btVector3 first = triangle.b - triangle.a;
            const btVector3 second = triangle.c - triangle.a;
            const btVector3 cross = outward.cross(second);
            const btScalar determinant = first.dot(cross);
            if (btFabs(determinant) < 1e-12f) return;
            const btVector3 offset = position - triangle.a;
            const btScalar u = offset.dot(cross) / determinant;
            if (u < -1e-5f || u > 1.00001f) return;
            const btVector3 perpendicular = offset.cross(first);
            const btScalar v = outward.dot(perpendicular) / determinant;
            if (v < -1e-5f || u + v > 1.00001f) return;
            const btScalar candidate = second.dot(perpendicular) / determinant;
            if (candidate < distance || candidate > 0.12f) return;
            const btVector3 point = position + outward * candidate;
            for (int axis = 0; axis < 3; ++axis) {
                if (point[axis] < searchMinimum[axis] || point[axis] > searchMaximum[axis]) return;
            }
            distance = candidate;
            bestTriangle = index;
        };
        const int hint = surfaceHints[hintIndex];
        if (hint >= 0) testTriangle(hint);
        std::array<int, 64> pending;
        int count = 1;
        pending[0] = surfaceRoots[group];
        while (count > 0) {
            const auto& node = surfaceNodes[pending[--count]];
            if ((skipArms && !node.hasTorso) || (onlyArms && !node.hasArms)) continue;
            if (!intersectsRay(node.minimum, node.maximum)) continue;
            if (node.left >= 0) {
                pending[count++] = node.left;
                pending[count++] = node.right;
                continue;
            }
            for (uint32_t slot = node.begin; slot < node.end; ++slot) {
                testTriangle(int(surfaceOrder[slot]));
            }
        }
        surfaceHints[hintIndex] = bestTriangle;
        return bestTriangle >= 0;
    }

    btScalar contactDepth(const btVector3& position, uint8_t armExclusions, size_t hintIndex,
                          btScalar gap, btVector3& normal, bool bodyOnly = false) {
        if (!finiteVector(position)) return 0;
        const bool skipBodyArms = (armExclusions & WEASHION_CLOTH_EXCLUDE_BODY_ARMS) != 0;
        const bool skipLayerArms = (armExclusions & WEASHION_CLOTH_EXCLUDE_LAYER_ARMS) != 0;
        const bool onlyLayerArms = (armExclusions & WEASHION_CLOTH_LAYER_ARMS_ONLY) != 0;
        btVector3 point, outward;
        bool hasOutward = nearestSurface(position, skipBodyArms, point, outward, hintIndex, 0);
        const bool hasSkin = hasOutward;
        const btVector3 skinNormal = hasSkin ? outward : btVector3(0, 0, 0);
        const btScalar skinDistance = hasSkin ? (position - point).dot(outward) : SIMD_INFINITY;
        btScalar depth = btMax(btScalar(0), gap - skinDistance);
        if (depth > 0) normal = outward;
        if (surfaceGroupCount == 1 || bodyOnly) return depth;
        if (hintIndex < contactAxes.size() && !contactAxes[hintIndex].fuzzyZero()) {
            const auto& axis = contactAxes[hintIndex];
            const btVector3 offset = position - contactOrigins[hintIndex];
            outward = directionOr(offset - axis * offset.dot(axis), outward);
            hasOutward = true;
        } else if (!hasOutward || skipBodyArms != skipLayerArms || onlyLayerArms) {
            hasOutward = nearestSurface(position, skipLayerArms, point, outward, hintIndex, 0, false, onlyLayerArms);
        }
        if (!hasOutward) return depth;
        for (int group = 1; group < surfaceGroupCount; ++group) {
            btScalar distance;
            // Intersect finite panels, not infinite inward-facing lining/hem half-spaces.
            if (outerLayerContact(position, outward, skipLayerArms, hintIndex, group, distance, onlyLayerArms)) {
                if (distance + gap > depth) {
                    depth = distance + gap;
                    normal = outward;
                }
            }
        }
        // A layer correction must slide along nearby skin, not push through the opposing arm.
        if (depth > 0 && hasSkin && skinDistance < gap + layerContactStep && normal.dot(skinNormal) < 0) {
            if (skinDistance < 0) {
                normal = skinNormal;
            } else {
                const btVector3 tangent = normal - skinNormal * normal.dot(skinNormal);
                normal = directionOr(tangent, skinNormal);
            }
        }
        return depth;
    }

    void clearGarment() {
        restPositions.clear();
        fitPositions.clear();
        positions.clear();
        directions.clear();
        contactOrigins.clear();
        contactAxes.clear();
        faces.clear();
        edges.clear();
        bends.clear();
        tethers.clear();
        edgeLambdas.clear();
        bendLambdas.clear();
        vertexAreas.clear();
        inverseMasses.clear();
        torsoOnly.clear();
        extensionLimits.clear();
        corrections.clear();
        surfaceHints.clear();
        correctionCounts.clear();
        completedSteps = 0;
        remainingOverlap = 0;
        remainingMovableOverlap = 0;
        movableOverlapEnergy = 0;
        finalContactPasses = 0;
        meanArea = 0;
    }

    btVector3 outsideBody(const btVector3& position, const btVector3&, uint8_t armExclusions, size_t hintIndex,
                         bool bodyOnly = false) {
        btVector3 normal;
        btScalar depth;
        return outsideBody(position, armExclusions, normal, depth, hintIndex, bodyOnly);
    }

    btVector3 outsideBody(const btVector3& position, uint8_t armExclusions, btVector3& normal, btScalar& depth, size_t hintIndex,
                         bool bodyOnly = false) {
        depth = contactDepth(position, armExclusions, hintIndex, clearance, normal, bodyOnly);
        const btScalar displacement = surfaceGroupCount > 1 ? btMin(depth, layerContactStep) : depth;
        return depth > 0 ? position + normal * displacement : position;
    }

    void solveDistance(const GarmentEdge& edge, btScalar target, btScalar compliance,
                       btScalar& lambda, bool extensionOnly) {
        const btVector3 delta = positions[edge.second] - positions[edge.first];
        const btScalar length = delta.length();
        if (length < 1e-6f) return;
        const btScalar constraint = length - target;
        if (extensionOnly && constraint <= 0) { lambda = 0; return; }
        const btScalar firstMass = inverseMasses[edge.first];
        const btScalar secondMass = inverseMasses[edge.second];
        if (firstMass + secondMass <= 0) return;
        const btScalar alpha = compliance * 4;
        const btScalar change = (-constraint - alpha * lambda) / (firstMass + secondMass + alpha);
        lambda += change;
        const btVector3 correction = delta * (change / length);
        positions[edge.first] -= correction * firstMass;
        positions[edge.second] += correction * secondMass;
    }

    bool solveFaceContacts(WeashionClothCancellationCheck isCancelled, bool bodyOnly = false) {
        std::fill(corrections.begin(), corrections.end(), btVector3(0, 0, 0));
        std::fill(correctionCounts.begin(), correctionCounts.end(), 0);
        for (size_t faceIndex = 0; faceIndex < faces.size(); ++faceIndex) {
            if (cancelled(isCancelled, faceIndex)) return false;
            const auto& face = faces[faceIndex];
            if (inverseMasses[face[0]] + inverseMasses[face[1]] + inverseMasses[face[2]] <= 0) continue;
            for (size_t sampleIndex = 0; sampleIndex < faceSamples.size(); ++sampleIndex) {
                const auto& weights = faceSamples[sampleIndex];
                const uint8_t armExclusions = faceArmExclusions(face, weights);
                btVector3 sample(0, 0, 0);
                btVector3 outward(0, 0, 0);
                for (int corner = 0; corner < 3; ++corner) {
                    sample += positions[face[corner]] * weights[corner];
                    outward += directions[face[corner]] * weights[corner];
                }
                const btVector3 correction = outsideBody(sample, outward, armExclusions,
                    positions.size() + faceIndex * faceSamples.size() + sampleIndex, bodyOnly) - sample;
                if (correction.length2() < 1e-10f) continue;
                btScalar denominator = 0;
                for (int corner = 0; corner < 3; ++corner) {
                    denominator += weights[corner] * weights[corner] * inverseMasses[face[corner]];
                }
                if (denominator <= 0) continue;
                for (int corner = 0; corner < 3; ++corner) {
                    if (weights[corner] == 0 || inverseMasses[face[corner]] == 0) continue;
                    corrections[face[corner]] += correction
                        * (weights[corner] * inverseMasses[face[corner]] / denominator);
                    correctionCounts[face[corner]] += 1;
                }
            }
        }
        for (size_t index = 0; index < positions.size(); ++index) {
            if (cancelled(isCancelled, index)) return false;
            if (correctionCounts[index] > 0) {
                btVector3 correction = corrections[index] / btScalar(correctionCounts[index]);
                if (surfaceGroupCount > 1 && correction.length2() > layerContactStep * layerContactStep) {
                    correction *= layerContactStep / correction.length();
                }
                positions[index] += correction;
                positions[index] = outsideBody(positions[index], directions[index], torsoOnly[index], index, bodyOnly);
            } else if (bodyOnly && inverseMasses[index] > 0) {
                positions[index] = outsideBody(positions[index], directions[index], torsoOnly[index], index, true);
            }
        }
        return true;
    }

    uint8_t faceArmExclusions(const std::array<int, 3>& face, const btVector3& weights) const {
        uint8_t mask = 7;
        for (int corner = 0; corner < 3; ++corner) {
            if (weights[corner] > 0) mask &= torsoOnly[face[corner]];
        }
        return mask;
    }

    void prepareContactSamples() {
        for (size_t faceIndex = 0; faceIndex < faces.size(); ++faceIndex) {
            const auto& face = faces[faceIndex];
            for (size_t sampleIndex = 0; sampleIndex < faceSamples.size(); ++sampleIndex) {
                btVector3 origin(0, 0, 0), axis(0, 0, 0);
                bool guided = true;
                for (int corner = 0; corner < 3; ++corner) {
                    const btScalar weight = faceSamples[sampleIndex][corner];
                    if (weight == 0) continue;
                    guided = guided && !contactAxes[face[corner]].fuzzyZero();
                    origin += contactOrigins[face[corner]] * weight;
                    axis += contactAxes[face[corner]] * weight;
                }
                if (guided && !axis.fuzzyZero()) {
                    const size_t index = positions.size() + faceIndex * faceSamples.size() + sampleIndex;
                    contactOrigins[index] = origin;
                    contactAxes[index] = axis.normalized();
                }
            }
        }
    }

    bool limitEdgeExtension(WeashionClothCancellationCheck isCancelled) {
        for (int pass = 0; pass < 4; ++pass) {
            for (size_t offset = 0; offset < edges.size(); ++offset) {
                if (cancelled(isCancelled, offset)) return false;
                const auto& edge = edges[pass % 2 == 0 ? offset : edges.size() - offset - 1];
                btScalar lambda = 0;
                const btScalar limit = (extensionLimits[edge.first] + extensionLimits[edge.second]) * 0.5f;
                solveDistance(edge, edge.restLength * (1 + limit), 0, lambda, true);
            }
        }
        return true;
    }

    bool finishMaterialProjection(WeashionClothCancellationCheck isCancelled) {
        for (int pass = 0; pass < 64; ++pass) {
            btScalar excess = 0;
            for (size_t index = 0; index < edges.size(); ++index) {
                if (cancelled(isCancelled, index)) return false;
                const auto& edge = edges[index];
                if (inverseMasses[edge.first] + inverseMasses[edge.second] <= 0) continue;
                const btScalar limit = (extensionLimits[edge.first] + extensionLimits[edge.second]) * 0.5f;
                const btScalar length = (positions[edge.first] - positions[edge.second]).length();
                excess = btMax(excess, length - edge.restLength * (1 + limit));
            }
            if (excess < 0.0001f) break;
            if (!limitEdgeExtension(isCancelled)) return false;
        }
        return true;
    }

    btScalar relativeInverseMass(size_t index) const {
        return btMax(btScalar(0.2f), btMin(meanArea / btMax(vertexAreas[index], btScalar(1e-9f)), btScalar(5)));
    }

    void buildTethers() {
        using Neighbor = std::pair<int, btScalar>;
        using Candidate = std::pair<btScalar, int>;
        std::vector<std::vector<Neighbor>> neighbors(restPositions.size());
        for (const auto& edge : edges) {
            neighbors[edge.first].emplace_back(edge.second, edge.restLength);
            neighbors[edge.second].emplace_back(edge.first, edge.restLength);
        }
        btScalar top = restPositions.front().y();
        for (const auto& position : restPositions) top = btMax(top, position.y());
        std::vector<btScalar> distances(restPositions.size(), SIMD_INFINITY);
        std::vector<int> roots(restPositions.size(), -1);
        std::priority_queue<Candidate, std::vector<Candidate>, std::greater<Candidate>> pending;
        for (size_t index = 0; index < restPositions.size(); ++index) {
            if (restPositions[index].y() < top - 0.02f) continue;
            distances[index] = 0;
            roots[index] = int(index);
            pending.emplace(0, int(index));
        }
        while (!pending.empty()) {
            const auto [distance, index] = pending.top();
            pending.pop();
            if (distance > distances[index]) continue;
            for (const auto& [neighbor, length] : neighbors[index]) {
                if (distance + length >= distances[neighbor]) continue;
                distances[neighbor] = distance + length;
                roots[neighbor] = roots[index];
                pending.emplace(distances[neighbor], neighbor);
            }
        }
        for (size_t index = 0; index < restPositions.size(); ++index) {
            if (roots[index] < 0 || roots[index] == int(index)) continue;
            const int root = roots[index];
            const btScalar restDistance = (restPositions[index] - restPositions[root]).length();
            const btScalar fittedDistance = (fitPositions[index] - fitPositions[root]).length();
            tethers.push_back({root, int(index), btMin(distances[index], btMax(restDistance, fittedDistance))});
        }
    }

    bool fitPass(btScalar& movement, WeashionClothCancellationCheck isCancelled) {
        const auto before = positions;
        std::fill(edgeLambdas.begin(), edgeLambdas.end(), 0);
        std::fill(bendLambdas.begin(), bendLambdas.end(), 0);
        // Static fitting: gravity is a small settling displacement, not accumulated velocity.
        const btVector3 sag(0, -gravityStep, 0);
        for (size_t index = 0; index < positions.size(); ++index) {
            if (cancelled(isCancelled, index)) return false;
            if (inverseMasses[index] > 0) positions[index] = positions[index] + sag;
        }
        for (int iteration = 0; iteration < 4; ++iteration) {
            for (size_t index = 0; index < bends.size(); ++index) {
                if (cancelled(isCancelled, index)) return false;
                solveDistance(bends[index], bends[index].restLength, bendingCompliance * 0.10f, bendLambdas[index], false);
            }
            for (size_t index = 0; index < edges.size(); ++index) {
                if (cancelled(isCancelled, index)) return false;
                const auto& edge = edges[index];
                const bool compressed = (positions[edge.second] - positions[edge.first]).length2()
                    < edge.restLength * edge.restLength;
                // Resisting compression makes excess fabric fold instead of vanishing into shorter edges.
                solveDistance(edge, edge.restLength, compressed ? 0.1f : 0.02f, edgeLambdas[index], false);
                btScalar limitLambda = 0;
                const btScalar limit = (extensionLimits[edge.first] + extensionLimits[edge.second]) * 0.5f;
                solveDistance(edge, edge.restLength * (1 + limit), 0, limitLambda, true);
            }
            for (size_t index = 0; index < tethers.size(); ++index) {
                if (cancelled(isCancelled, index)) return false;
                const auto& tether = tethers[index];
                if (inverseMasses[tether.second] == 0) continue;
                const btVector3 delta = positions[tether.second] - positions[tether.first];
                const btScalar length = delta.length();
                const btScalar limit = tether.restLength * (1 + btMin(extensionLimits[tether.second], btScalar(0.02f)));
                if (length > limit && length > 1e-6f) {
                    positions[tether.second] -= delta * ((length - limit) / length);
                }
            }
            if (iteration % 2 == 0) continue;
            for (size_t index = 0; index < positions.size(); ++index) {
                if (cancelled(isCancelled, index)) return false;
                if (inverseMasses[index] > 0) {
                    btVector3 normal;
                    btScalar depth;
                    positions[index] = outsideBody(positions[index], torsoOnly[index], normal, depth, index);
                    if (depth <= 0) continue;
                    // Coulomb-like contact friction keeps fabric resting on sloped surfaces such as the shoulders.
                    const btVector3 moved = positions[index] - before[index];
                    const btVector3 tangential = moved - normal * moved.dot(normal);
                    const btScalar length = tangential.length();
                    if (length > 1e-9f) positions[index] -= tangential * btMin(btScalar(1), 0.8f * depth / length);
                }
            }
        }
        if ((completedSteps + 1) % 3 == 0 && !solveFaceContacts(isCancelled)) return false;
        movement = 0;
        for (size_t index = 0; index < positions.size(); ++index) {
            movement = btMax(movement, (positions[index] - before[index]).length());
        }
        return true;
    }

    // Sampled depth below skin or a layer envelope, excluding clearance.
    btScalar penetration(const btVector3& position, uint8_t armExclusions, size_t hintIndex, bool bodyOnly = false) {
        btVector3 normal;
        return contactDepth(position, armExclusions, hintIndex, 0, normal, bodyOnly);
    }

    bool measureOverlap(WeashionClothCancellationCheck isCancelled, bool bodyOnly = false) {
        remainingOverlap = 0;
        remainingMovableOverlap = 0;
        movableOverlapEnergy = 0;
        for (size_t index = 0; index < positions.size(); ++index) {
            if (cancelled(isCancelled, index)) return false;
            const btScalar depth = penetration(positions[index], torsoOnly[index], index, bodyOnly);
            remainingOverlap = btMax(remainingOverlap, depth);
            if (inverseMasses[index] > 0) {
                remainingMovableOverlap = btMax(remainingMovableOverlap, depth);
                movableOverlapEnergy += depth * depth;
            }
        }
        for (size_t faceIndex = 0; faceIndex < faces.size(); ++faceIndex) {
            if (cancelled(isCancelled, faceIndex)) return false;
            const auto& face = faces[faceIndex];
            for (size_t sampleIndex = 0; sampleIndex < faceSamples.size(); ++sampleIndex) {
                const auto& weights = faceSamples[sampleIndex];
                const uint8_t armExclusions = faceArmExclusions(face, weights);
                btVector3 sample(0, 0, 0);
                btScalar mobility = 0;
                for (int corner = 0; corner < 3; ++corner) {
                    sample += positions[face[corner]] * weights[corner];
                    mobility += weights[corner] * weights[corner] * inverseMasses[face[corner]];
                }
                const btScalar depth = penetration(sample, armExclusions,
                    positions.size() + faceIndex * faceSamples.size() + sampleIndex, bodyOnly);
                remainingOverlap = btMax(remainingOverlap, depth);
                if (mobility > 0) {
                    remainingMovableOverlap = btMax(remainingMovableOverlap, depth);
                    movableOverlapEnergy += depth * depth;
                }
            }
        }
        return true;
    }

};

extern "C" WeashionCloth *weashion_cloth_create_layered_body(
    const float *vertices, int32_t vertexCount, const int32_t *indices, int32_t triangleCount,
    const uint8_t *armTriangles, const uint8_t *surfaceGroups) {
    if (!vertices || !indices || vertexCount < 3 || vertexCount > 200000 ||
        triangleCount < 1 || triangleCount > 400000) return nullptr;
    try {
        auto cloth = std::make_unique<WeashionCloth>();
        cloth->triangles.reserve(triangleCount);
        for (int triangle = 0; triangle < triangleCount; ++triangle) {
            const uint8_t group = surfaceGroups ? surfaceGroups[triangle] : 0;
            if (group > 3) return nullptr;
            cloth->surfaceGroupCount = std::max(cloth->surfaceGroupCount, int(group) + 1);
            btVector3 corners[3];
            for (int corner = 0; corner < 3; ++corner) {
                const int index = indices[triangle * 3 + corner];
                if (index < 0 || index >= vertexCount) return nullptr;
                const float *point = vertices + index * 3;
                corners[corner] = btVector3(point[0], point[1], point[2]);
                if (!finiteVector(corners[corner])) return nullptr;
            }
            const btVector3 normal = (corners[1] - corners[0]).cross(corners[2] - corners[0]);
            if (!finiteVector(normal) || normal.fuzzyZero()) continue;
            btVector3 minimum = corners[0], maximum = corners[0];
            for (int corner = 1; corner < 3; ++corner) {
                minimum.setMin(corners[corner]);
                maximum.setMax(corners[corner]);
            }
            cloth->triangles.push_back({corners[0], corners[1], corners[2], normal.normalized(),
                                        armTriangles && armTriangles[triangle] != 0, group, minimum, maximum});
        }
        if (cloth->triangles.empty()) return nullptr;
        cloth->indexBody();
        if (cloth->surfaceRoots[0] < 0) return nullptr;
        return cloth.release();
    } catch (...) {
        return nullptr;
    }
}

extern "C" WeashionCloth *weashion_cloth_create_body(
    const float *vertices, int32_t vertexCount, const int32_t *indices, int32_t triangleCount,
    const uint8_t *armTriangles) {
    return weashion_cloth_create_layered_body(vertices, vertexCount, indices, triangleCount, armTriangles, nullptr);
}

extern "C" int32_t weashion_cloth_set_garment(
    WeashionCloth *cloth, const float *positions, int32_t vertexCount,
    const int32_t *triangles, int32_t triangleCount, const float *fittedPositions) {
    if (!cloth || !positions || !triangles || !fittedPositions || vertexCount < 3 || vertexCount > 12000 ||
        triangleCount < 1 || triangleCount > 40000) return 0;
    for (int index = 0; index < vertexCount * 3; ++index) {
        if (!std::isfinite(positions[index]) || !std::isfinite(fittedPositions[index])) return 0;
    }
    for (int index = 0; index < triangleCount * 3; ++index) {
        if (triangles[index] < 0 || triangles[index] >= vertexCount) return 0;
    }
    cloth->clearGarment();
    try {
        cloth->restPositions.reserve(vertexCount);
        cloth->fitPositions.reserve(vertexCount);
        for (int index = 0; index < vertexCount; ++index) {
            cloth->restPositions.emplace_back(positions[index * 3], positions[index * 3 + 1], positions[index * 3 + 2]);
            cloth->fitPositions.emplace_back(fittedPositions[index * 3], fittedPositions[index * 3 + 1], fittedPositions[index * 3 + 2]);
        }
        cloth->positions = cloth->restPositions;
        cloth->directions.resize(vertexCount, btVector3(0, 0, 0));
        cloth->vertexAreas.resize(vertexCount, 0);
        cloth->inverseMasses.resize(vertexCount, 0);
        cloth->torsoOnly.assign(vertexCount, 0);
        cloth->extensionLimits.assign(vertexCount, 0.08f);
        cloth->corrections.resize(vertexCount);
        cloth->correctionCounts.resize(vertexCount);
        std::unordered_map<uint64_t, size_t> connected;
        connected.reserve(triangleCount * 2);
        for (int triangle = 0; triangle < triangleCount; ++triangle) {
            const int32_t *face = triangles + triangle * 3;
            const auto& first = cloth->positions[face[0]];
            const auto& second = cloth->positions[face[1]];
            const auto& third = cloth->positions[face[2]];
            const btVector3 normal = (second - first).cross(third - first);
            if (normal.length2() < 1e-14f) {
                cloth->clearGarment();
                return 0;
            }
            cloth->faces.push_back({face[0], face[1], face[2]});
            for (int corner = 0; corner < 3; ++corner) {
                const int start = face[corner];
                const int end = face[(corner + 1) % 3];
                const int opposite = face[(corner + 2) % 3];
                cloth->vertexAreas[start] += normal.length() / 6;
                const auto insertion = connected.emplace(edgeKey(start, end), cloth->edges.size());
                if (insertion.second) {
                    cloth->edges.push_back({start, end, (cloth->positions[start] - cloth->positions[end]).length(), opposite});
                } else {
                    auto& edge = cloth->edges[insertion.first->second];
                    if (edge.opposite >= 0 && edge.opposite != opposite) {
                        const btScalar distance = (cloth->positions[edge.opposite] - cloth->positions[opposite]).length();
                        if (distance > 1e-6f) cloth->bends.push_back({edge.opposite, opposite, distance});
                        edge.opposite = -1;
                    }
                }
            }
        }
        cloth->buildTethers();
        for (const auto& face : cloth->faces) {
            const btVector3 normal = (cloth->fitPositions[face[1]] - cloth->fitPositions[face[0]]).cross(
                cloth->fitPositions[face[2]] - cloth->fitPositions[face[0]]);
            for (const int index : face) cloth->directions[index] += normal;
        }
        for (int index = 0; index < vertexCount; ++index) {
            const auto& point = cloth->restPositions[index];
            const btVector3 fallback = directionOr(btVector3(point.x(), 0, point.z()), btVector3(0, 1, 0));
            cloth->directions[index] = directionOr(cloth->directions[index], fallback);
            cloth->meanArea += cloth->vertexAreas[index] / btScalar(vertexCount);
        }
        for (int index = 0; index < vertexCount; ++index) {
            cloth->inverseMasses[index] = cloth->relativeInverseMass(index);
        }
        cloth->edgeLambdas.resize(cloth->edges.size(), 0);
        cloth->bendLambdas.resize(cloth->bends.size(), 0);
        cloth->positions = cloth->fitPositions;
        cloth->surfaceHints.assign((size_t(vertexCount) + size_t(triangleCount) * faceSamples.size())
                                  * size_t(cloth->surfaceGroupCount), -1);
        return 1;
    } catch (...) {
        cloth->clearGarment();
        return 0;
    }
}

extern "C" int32_t weashion_cloth_configure(
    WeashionCloth *cloth, const uint8_t *torsoOnly, const float *extensionLimits,
    int32_t vertexCount, float bendingCompliance, float surfaceDensity) {
    if (!cloth || !extensionLimits || vertexCount != int32_t(cloth->positions.size()) ||
        !std::isfinite(bendingCompliance) || bendingCompliance < 0 || bendingCompliance > 100 ||
        !std::isfinite(surfaceDensity) || surfaceDensity < 0.05f || surfaceDensity > 1) return 0;
    for (int index = 0; index < vertexCount; ++index) {
        if (!std::isfinite(extensionLimits[index]) || extensionLimits[index] < 0 || extensionLimits[index] > 0.5f) return 0;
        cloth->extensionLimits[index] = extensionLimits[index];
        if (torsoOnly && (torsoOnly[index] > 7 || (torsoOnly[index] & 6) == 6)) return 0;
        cloth->torsoOnly[index] = torsoOnly ? torsoOnly[index] : 0;
    }
    cloth->bendingCompliance = bendingCompliance;
    cloth->gravityStep = 0.0015f * surfaceDensity / 0.18f;
    return 1;
}

extern "C" int32_t weashion_cloth_set_contact_guides(
    WeashionCloth *cloth, const float *origins, const float *axes, int32_t vertexCount) {
    if (!cloth || !origins || !axes || vertexCount != int32_t(cloth->positions.size())) return 0;
    for (int index = 0; index < vertexCount; ++index) {
        const btVector3 origin(origins[index * 3], origins[index * 3 + 1], origins[index * 3 + 2]);
        const btVector3 axis(axes[index * 3], axes[index * 3 + 1], axes[index * 3 + 2]);
        if (!finiteVector(origin) || !finiteVector(axis)
            || (!axis.fuzzyZero() && btFabs(axis.length2() - 1) > 0.001f)) return 0;
    }
    const size_t samples = cloth->positions.size() + cloth->faces.size() * faceSamples.size();
    cloth->contactOrigins.assign(samples, btVector3(0, 0, 0));
    cloth->contactAxes.assign(samples, btVector3(0, 0, 0));
    for (int index = 0; index < vertexCount; ++index) {
        cloth->contactOrigins[index] = btVector3(origins[index * 3], origins[index * 3 + 1], origins[index * 3 + 2]);
        cloth->contactAxes[index] = btVector3(axes[index * 3], axes[index * 3 + 1], axes[index * 3 + 2]);
    }
    cloth->prepareContactSamples();
    return 1;
}

extern "C" void weashion_cloth_clear_garment(WeashionCloth *cloth) {
    if (cloth) cloth->clearGarment();
}

extern "C" int32_t weashion_cloth_pin_vertices(WeashionCloth *cloth, const int32_t *indices, int32_t count) {
    if (!cloth || count < 0 || count > int32_t(cloth->positions.size()) || (count > 0 && !indices)) return 0;
    for (int32_t index = 0; index < count; ++index) {
        if (indices[index] < 0 || indices[index] >= int32_t(cloth->positions.size())) return 0;
    }
    for (int32_t index = 0; index < count; ++index) cloth->inverseMasses[indices[index]] = 0;
    return 1;
}

extern "C" int32_t weashion_cloth_step(WeashionCloth *cloth, int32_t steps, WeashionClothCancellationCheck isCancelled) {
    if (!cloth || cloth->positions.empty()) return 0;
    if (cancelled(isCancelled, 0)) return -1;
    if (cloth->completedSteps >= 72) return 2;
    for (int step = 0; step < std::min(std::max(int(steps), 1), 8); ++step) {
        btScalar movement = 0;
        if (!cloth->fitPass(movement, isCancelled)) return -1;
        for (const auto& position : cloth->positions) {
            if (!finiteVector(position)) return 0;
        }
        cloth->completedSteps += 1;
        if ((cloth->completedSteps >= 9 && movement < 0.001f && cloth->completedSteps % 3 == 0)
            || cloth->completedSteps >= 72) {
            cloth->completedSteps = 72;
            if (!cloth->limitEdgeExtension(isCancelled) || !cloth->measureOverlap(isCancelled)) return -1;
            auto previousPositions = cloth->positions;
            btScalar previousOverlap = cloth->remainingMovableOverlap;
            auto bestPositions = cloth->positions;
            btScalar bestEnergy = cloth->movableOverlapEnergy;
            int stationaryBatches = 0;
            int stalledBatches = 0;
            for (int pass = 0; pass < 96 && cloth->remainingMovableOverlap > 0.001f; ++pass) {
                if (!cloth->solveFaceContacts(isCancelled) || !cloth->limitEdgeExtension(isCancelled)) return -1;
                cloth->finalContactPasses += 1;
                // Batch convergence checks, not contact corrections; the final residual is always measured.
                if ((pass + 1) % 4 == 0) {
                    if (!cloth->measureOverlap(isCancelled)) return -1;
                    btScalar movement = 0;
                    for (size_t index = 0; index < cloth->positions.size(); ++index) {
                        if (cancelled(isCancelled, index)) return -1;
                        movement = btMax(movement, (cloth->positions[index] - previousPositions[index]).length2());
                    }
                    const bool stationary = movement < 0.00005f * 0.00005f
                        && btFabs(cloth->remainingMovableOverlap - previousOverlap) < 0.00005f;
                    stationaryBatches = stationary ? stationaryBatches + 1 : 0;
                    previousPositions = cloth->positions;
                    previousOverlap = cloth->remainingMovableOverlap;
                    if (cloth->surfaceGroupCount > 1) {
                        const bool improving = cloth->movableOverlapEnergy < bestEnergy * 0.999f;
                        if (cloth->movableOverlapEnergy < bestEnergy) {
                            bestEnergy = cloth->movableOverlapEnergy;
                            bestPositions = cloth->positions;
                        }
                        stalledBatches = improving ? 0 : stalledBatches + 1;
                        if (stalledBatches >= 3) break;
                    }
                    if (stationaryBatches >= 2) break;
                }
            }
            if (cloth->surfaceGroupCount > 1) {
                cloth->positions = std::move(bestPositions);
                if (!cloth->finishMaterialProjection(isCancelled) || !cloth->measureOverlap(isCancelled, true)) return -1;
                // Material correction must not be the last operation if it reintroduces skin penetration.
                for (int pass = 0; pass < 16 && cloth->remainingMovableOverlap > 0.001f; ++pass) {
                    if (!cloth->solveFaceContacts(isCancelled, true) || !cloth->measureOverlap(isCancelled, true)) return -1;
                    cloth->finalContactPasses += 1;
                }
                if (!cloth->measureOverlap(isCancelled)) return -1;
            }
            return std::isfinite(cloth->remainingOverlap) ? 2 : 0;
        }
    }
    return 1;
}

extern "C" int32_t weashion_cloth_project_shape(
    WeashionCloth *cloth, const float *maximumDisplacements, int32_t vertexCount,
    int32_t passes, WeashionClothCancellationCheck isCancelled) {
    if (!cloth || !maximumDisplacements || cloth->positions.empty() || cloth->completedSteps != 0 ||
        vertexCount != int32_t(cloth->positions.size()) || passes < 1 || passes > 16) return 0;
    for (int index = 0; index < vertexCount; ++index) {
        if (!std::isfinite(maximumDisplacements[index]) || maximumDisplacements[index] < 0 ||
            maximumDisplacements[index] > 0.04f) return 0;
    }
    if (cancelled(isCancelled, 0)) return -1;
    for (int index = 0; index < vertexCount; ++index) {
        if (maximumDisplacements[index] == 0) cloth->inverseMasses[index] = 0;
    }
    std::vector<int> neighborCounts(vertexCount, 0);
    for (const auto& edge : cloth->edges) {
        neighborCounts[edge.first] += 1;
        neighborCounts[edge.second] += 1;
    }
    std::vector<btVector3> offsets(vertexCount);
    std::vector<btVector3> neighborOffsets(vertexCount);
    auto faceNormal = [&](size_t index, const std::vector<btVector3>& positions) {
        const auto& face = cloth->faces[index];
        return (positions[face[1]] - positions[face[0]]).cross(positions[face[2]] - positions[face[0]]);
    };
    std::vector<btVector3> fittedNormals;
    for (size_t index = 0; index < cloth->faces.size(); ++index) {
        fittedNormals.push_back(faceNormal(index, cloth->fitPositions));
    }
    std::unordered_map<uint64_t, size_t> adjacentFaces;
    std::vector<std::array<size_t, 2>> unfoldedHinges;
    for (size_t index = 0; index < cloth->faces.size(); ++index) {
        if (cancelled(isCancelled, index)) return -1;
        const auto& face = cloth->faces[index];
        for (int corner = 0; corner < 3; ++corner) {
            const auto key = edgeKey(face[corner], face[(corner + 1) % 3]);
            const auto previous = adjacentFaces.find(key);
            if (previous == adjacentFaces.end()) {
                adjacentFaces.emplace(key, index);
            } else if (fittedNormals[index].dot(fittedNormals[previous->second]) > 0) {
                unfoldedHinges.push_back({previous->second, index});
            }
        }
    }
    auto validFace = [&](size_t index, btScalar minimumCosine) {
        const btVector3 normal = faceNormal(index, cloth->positions);
        const auto& reference = fittedNormals[index];
        return normal.length2() >= reference.length2() * 0.01f
            && normal.dot(reference) >= minimumCosine * btSqrt(normal.length2() * reference.length2());
    };
    auto validHinge = [&](const std::array<size_t, 2>& hinge, btScalar minimumCosine) {
        const btVector3 first = faceNormal(hinge[0], cloth->positions);
        const btVector3 second = faceNormal(hinge[1], cloth->positions);
        return first.dot(second) >= minimumCosine * btSqrt(first.length2() * second.length2());
    };
    for (int pass = 0; pass < passes; ++pass) {
        const auto before = cloth->positions;
        if (!cloth->solveFaceContacts(isCancelled)) return -1;
        // Preserve the fitted panel shape across each edge as well as along it.
        auto preserveDistance = [&](const GarmentEdge& edge, btScalar tolerance) {
            const btScalar reference = (cloth->fitPositions[edge.second] - cloth->fitPositions[edge.first]).length();
            const btScalar length = (cloth->positions[edge.second] - cloth->positions[edge.first]).length();
            if (length >= reference * (1 - tolerance) && length <= reference * (1 + tolerance)) return;
            btScalar lambda = 0;
            cloth->solveDistance(edge, reference * (length < reference ? 1 - tolerance : 1 + tolerance),
                                 0, lambda, false);
        };
        for (int sweep = 0; sweep < 6; ++sweep) {
            for (size_t index = 0; index < cloth->edges.size(); ++index) {
                if (cancelled(isCancelled, index)) return -1;
                preserveDistance(cloth->edges[index], 0.10f);
            }
            for (size_t index = 0; index < cloth->bends.size(); ++index) {
                if (cancelled(isCancelled, index)) return -1;
                preserveDistance(cloth->bends[index], 0.02f);
            }
        }
        // Smooth the contact displacement field, leaving the garment's original folds intact.
        for (int index = 0; index < vertexCount; ++index) {
            offsets[index] = cloth->positions[index] - before[index];
        }
        for (int sweep = 0; sweep < 16; ++sweep) {
            std::fill(neighborOffsets.begin(), neighborOffsets.end(), btVector3(0, 0, 0));
            for (size_t index = 0; index < cloth->edges.size(); ++index) {
                if (cancelled(isCancelled, index)) return -1;
                const auto& edge = cloth->edges[index];
                neighborOffsets[edge.first] += offsets[edge.second];
                neighborOffsets[edge.second] += offsets[edge.first];
            }
            for (int index = 0; index < vertexCount; ++index) {
                if (cloth->inverseMasses[index] == 0) {
                    offsets[index] = btVector3(0, 0, 0);
                } else if (neighborCounts[index] > 0) {
                    offsets[index] = (offsets[index] + neighborOffsets[index] / btScalar(neighborCounts[index])) * 0.5f;
                }
            }
        }
        btScalar movement = 0;
        for (int index = 0; index < vertexCount; ++index) {
            if (cancelled(isCancelled, index)) return -1;
            if (cloth->inverseMasses[index] == 0) {
                cloth->positions[index] = cloth->fitPositions[index];
                continue;
            }
            btVector3 step = offsets[index];
            if (step.length2() > 0.004f * 0.004f) step *= 0.004f / step.length();
            btVector3 offset = before[index] + step - cloth->fitPositions[index];
            const btScalar limit = maximumDisplacements[index];
            if (offset.length2() > limit * limit) offset *= limit / offset.length();
            cloth->positions[index] = cloth->fitPositions[index] + offset;
            if (!finiteVector(cloth->positions[index])) return 0;
        }
        bool safe = false;
        for (int sweep = 0; sweep < 24; ++sweep) {
            safe = true;
            for (size_t index = 0; index < cloth->faces.size(); ++index) {
                if (cancelled(isCancelled, index)) return -1;
                const auto& face = cloth->faces[index];
                if (validFace(index, 0.6f)) continue;
                safe = false;
                for (int corner : face) cloth->positions[corner] = (before[corner] + cloth->positions[corner]) * 0.5f;
            }
            for (size_t index = 0; index < unfoldedHinges.size(); ++index) {
                if (cancelled(isCancelled, index)) return -1;
                const auto& hinge = unfoldedHinges[index];
                if (validHinge(hinge, 0.02f)) continue;
                safe = false;
                const auto& first = cloth->faces[hinge[0]];
                const auto& second = cloth->faces[hinge[1]];
                for (int corner : first) cloth->positions[corner] = (before[corner] + cloth->positions[corner]) * 0.5f;
                for (int corner : second) {
                    if (std::find(first.begin(), first.end(), corner) == first.end()) {
                        cloth->positions[corner] = (before[corner] + cloth->positions[corner]) * 0.5f;
                    }
                }
            }
            if (safe) break;
        }
        if (!safe) {
            for (size_t index = 0; index < cloth->faces.size(); ++index) {
                if (cancelled(isCancelled, index)) return -1;
                if (!validFace(index, 0.5f)) return 0;
            }
            for (size_t index = 0; index < unfoldedHinges.size(); ++index) {
                if (cancelled(isCancelled, index)) return -1;
                if (!validHinge(unfoldedHinges[index], 0)) return 0;
            }
        }
        for (int index = 0; index < vertexCount; ++index) {
            movement = btMax(movement, (cloth->positions[index] - before[index]).length2());
        }
        cloth->finalContactPasses += 1;
        if (movement < 0.00005f * 0.00005f) break;
    }
    if (!cloth->measureOverlap(isCancelled)) return -1;
    cloth->completedSteps = 72;
    return std::isfinite(cloth->remainingOverlap) ? 2 : 0;
}

extern "C" void weashion_cloth_copy_positions(const WeashionCloth *cloth, float *positions) {
    if (!cloth || !positions) return;
    for (size_t index = 0; index < cloth->positions.size(); ++index) {
        const auto& position = cloth->positions[index];
        positions[index * 3] = position.x();
        positions[index * 3 + 1] = position.y();
        positions[index * 3 + 2] = position.z();
    }
}

// Ignore sub-5 mm seam edges, but never hide a stretched visible edge in a percentile.
extern "C" float weashion_cloth_max_strain(const WeashionCloth *cloth) {
    if (!cloth) return 0;
    btScalar maximum = 0;
    for (const auto& edge : cloth->edges) {
        if (edge.restLength < 0.005f) continue;
        const btScalar length = (cloth->positions[edge.first] - cloth->positions[edge.second]).length();
        maximum = btMax(maximum, length / edge.restLength - 1);
    }
    return maximum;
}

extern "C" float weashion_cloth_remaining_overlap(const WeashionCloth *cloth) {
    return cloth ? cloth->remainingOverlap : 0;
}

extern "C" int32_t weashion_cloth_final_contact_passes(const WeashionCloth *cloth) {
    return cloth ? cloth->finalContactPasses : 0;
}

extern "C" float weashion_cloth_body_depth(WeashionCloth *cloth, const float *position) {
    if (!cloth || !position) return NAN;
    const btVector3 sample(position[0], position[1], position[2]);
    if (!finiteVector(sample)) return NAN;
    btVector3 point, normal;
    return cloth->nearestSurface(sample, false, point, normal, 0, 0)
        ? btMax(btScalar(0), -(sample - point).dot(normal)) : 0;
}

extern "C" int32_t weashion_cloth_measure_body_overlap(
    WeashionCloth *cloth, const float *positions, int32_t vertexCount,
    const int32_t *indices, int32_t triangleCount, float *overlap,
    WeashionClothCancellationCheck isCancelled) {
    if (!cloth || !positions || !indices || !overlap || vertexCount < 3 || vertexCount > 200000
        || triangleCount < 1 || triangleCount > 400000) return 0;
    btScalar maximum = 0;
    for (int32_t index = 0; index < vertexCount; ++index) {
        if (cancelled(isCancelled, index)) return -1;
        const auto depth = weashion_cloth_body_depth(cloth, positions + index * 3);
        if (!std::isfinite(depth)) return 0;
        maximum = btMax(maximum, depth);
    }
    for (int32_t face = 0; face < triangleCount; ++face) {
        if (cancelled(isCancelled, face)) return -1;
        const auto* corners = indices + face * 3;
        for (int corner = 0; corner < 3; ++corner) {
            if (corners[corner] < 0 || corners[corner] >= vertexCount) return 0;
        }
        for (const auto& weights : faceSamples) {
            btVector3 point(0, 0, 0);
            for (int corner = 0; corner < 3; ++corner) {
                const auto* vertex = positions + corners[corner] * 3;
                point += btVector3(vertex[0], vertex[1], vertex[2]) * weights[corner];
            }
            const float sample[3] = {point.x(), point.y(), point.z()};
            maximum = btMax(maximum, weashion_cloth_body_depth(cloth, sample));
        }
    }
    *overlap = maximum;
    return 1;
}

extern "C" void weashion_cloth_destroy(WeashionCloth *cloth) {
    delete cloth;
}