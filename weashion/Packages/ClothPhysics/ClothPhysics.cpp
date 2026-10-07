#include "ClothPhysics.h"
#include "LinearMath/btConvexHullComputer.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <memory>
#include <unordered_set>
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
};

static const std::array<btVector3, 4> faceSamples = {
    btVector3(0.5f, 0.5f, 0), btVector3(0, 0.5f, 0.5f),
    btVector3(0.5f, 0, 0.5f), btVector3(1.0f / 3, 1.0f / 3, 1.0f / 3)
};

static btVector3 directionOr(const btVector3& direction, const btVector3& fallback) {
    return direction.length2() > 1e-12f ? direction.normalized() : fallback;
}

struct CollisionPlane {
    btVector3 normal;
    btScalar offset;
};

struct CollisionBand {
    std::vector<CollisionPlane> planes;
    btVector3 center;
    btVector3 minimum;
    btVector3 maximum;
};

struct WeashionCloth {
    std::vector<CollisionBand> bands;
    std::array<std::vector<size_t>, 128> heightBands;
    btScalar minimumHeight = 0;
    btScalar maximumHeight = 0;
    btScalar heightToBucket = 0;
    std::vector<btVector3> restPositions;
    std::vector<btVector3> fitPositions;
    std::vector<btVector3> positions;
    std::vector<btVector3> directions;
    std::vector<std::array<int, 3>> faces;
    std::vector<GarmentEdge> edges;
    std::vector<std::vector<int>> neighbors;
    std::vector<btVector3> corrections;
    std::vector<int> correctionCounts;
    int completedSteps = 0;
    btScalar remainingOverlap = 0;

    size_t heightBucket(btScalar height) const {
        const btScalar bucket = (height - minimumHeight) * heightToBucket;
        return size_t(btMax(btScalar(0), btMin(bucket, btScalar(heightBands.size() - 1))));
    }

    void indexBody() {
        minimumHeight = bands.front().minimum.y();
        maximumHeight = minimumHeight;
        for (const auto& band : bands) maximumHeight = btMax(maximumHeight, band.maximum.y());
        heightToBucket = btScalar(heightBands.size()) / btMax(maximumHeight - minimumHeight, btScalar(0.001f));
        for (size_t index = 0; index < bands.size(); ++index) {
            for (size_t bucket = heightBucket(bands[index].minimum.y()); bucket <= heightBucket(bands[index].maximum.y()); ++bucket) {
                heightBands[bucket].push_back(index);
            }
        }
    }

    bool faceMayTouchBody(const std::array<int, 3>& face) const {
        btVector3 minimum = positions[face[0]];
        btVector3 maximum = minimum;
        for (int corner = 1; corner < 3; ++corner) {
            minimum.setMin(positions[face[corner]]);
            maximum.setMax(positions[face[corner]]);
        }
        if (!finiteVector(minimum) || !finiteVector(maximum)) return false;
        if (maximum.y() < minimumHeight || minimum.y() > maximumHeight) return false;
        const btScalar clearance = 0.004f;
        for (size_t bucket = heightBucket(minimum.y()); bucket <= heightBucket(maximum.y()); ++bucket) {
            for (const size_t index : heightBands[bucket]) {
                const auto& band = bands[index];
                if (maximum.x() >= band.minimum.x() - clearance && minimum.x() <= band.maximum.x() + clearance &&
                    maximum.y() >= band.minimum.y() && minimum.y() <= band.maximum.y() &&
                    maximum.z() >= band.minimum.z() - clearance && minimum.z() <= band.maximum.z() + clearance) return true;
            }
        }
        return false;
    }

    void clearGarment() {
        restPositions.clear();
        fitPositions.clear();
        positions.clear();
        directions.clear();
        faces.clear();
        edges.clear();
        neighbors.clear();
        corrections.clear();
        correctionCounts.clear();
        completedSteps = 0;
        remainingOverlap = 0;
    }

    btVector3 outsideBody(btVector3 position, const btVector3& outward) {
        if (!finiteVector(position) || position.y() < minimumHeight || position.y() > maximumHeight) return position;
        const btScalar clearance = 0.004f;
        std::vector<btVector3> candidates;
        for (const size_t index : heightBands[heightBucket(position.y())]) {
            const auto& band = bands[index];
            if (position.x() < band.minimum.x() - clearance || position.x() > band.maximum.x() + clearance ||
                position.y() < band.minimum.y() - clearance || position.y() > band.maximum.y() + clearance ||
                position.z() < band.minimum.z() - clearance || position.z() > band.maximum.z() + clearance) continue;
            bool inside = true;
            btScalar nearest = SIMD_INFINITY;
            btVector3 normal(0, 1, 0);
            for (const auto& plane : band.planes) {
                const btScalar distance = plane.offset + clearance - plane.normal.dot(position);
                if (distance <= 0) { inside = false; break; }
                if (distance < nearest) { nearest = distance; normal = plane.normal; }
            }
            if (inside) candidates.push_back(normal);
        }
        if (candidates.empty()) return position;
        const btVector3 preferred = directionOr(outward, btVector3(0, 1, 0));
        candidates.push_back(preferred);
        for (int axis = 0; axis < 3; ++axis) {
            btVector3 direction(0, 0, 0);
            direction[axis] = 1;
            candidates.push_back(direction);
            candidates.push_back(-direction);
        }
        btScalar bestScore = SIMD_INFINITY;
        btVector3 correction(0, 0, 0);
        std::vector<std::pair<btScalar, btScalar>> intervals;
        intervals.reserve(bands.size());
        for (const auto& direction : candidates) {
            intervals.clear();
            for (const auto& band : bands) {
                btScalar entry = 0;
                btScalar exit = SIMD_INFINITY;
                bool intersects = true;
                for (int axis = 0; axis < 3; ++axis) {
                    if (btFabs(direction[axis]) < 1e-6f) {
                        if (position[axis] < band.minimum[axis] - clearance || position[axis] > band.maximum[axis] + clearance) {
                            intersects = false;
                            break;
                        }
                    } else {
                        const btScalar first = (band.minimum[axis] - clearance - position[axis]) / direction[axis];
                        const btScalar second = (band.maximum[axis] + clearance - position[axis]) / direction[axis];
                        entry = btMax(entry, btMin(first, second));
                        exit = btMin(exit, btMax(first, second));
                        if (exit < entry) { intersects = false; break; }
                    }
                }
                if (!intersects) continue;
                for (const auto& plane : band.planes) {
                    const btScalar distance = plane.offset + clearance - plane.normal.dot(position);
                    const btScalar alignment = plane.normal.dot(direction);
                    if (alignment > 1e-6f) exit = btMin(exit, distance / alignment);
                    else if (alignment < -1e-6f) entry = btMax(entry, distance / alignment);
                    else if (distance < 0) { intersects = false; break; }
                    if (exit < entry) { intersects = false; break; }
                }
                if (intersects && exit >= 0) intervals.emplace_back(entry, exit);
            }
            std::sort(intervals.begin(), intervals.end());
            btScalar distance = 0;
            for (const auto& interval : intervals) {
                if (interval.first > distance + 0.00002f) break;
                distance = btMax(distance, interval.second);
            }
            const btScalar score = distance * (1 + 0.05f * (1 - preferred.dot(direction)));
            if (distance > 0 && score < bestScore) {
                bestScore = score;
                correction = direction * (distance + 0.00002f);
            }
        }
        return position + correction;
    }

    bool fitPass(btScalar& movement, WeashionClothCancellationCheck isCancelled, bool relax = true) {
        const auto before = positions;
        for (size_t index = 0; relax && index < positions.size(); ++index) {
            if (cancelled(isCancelled, index)) return false;
            if (neighbors[index].empty()) continue;
            btVector3 average(0, 0, 0);
            for (const int neighbor : neighbors[index]) average += before[neighbor] - fitPositions[neighbor];
            average /= btScalar(neighbors[index].size());
            positions[index] = fitPositions[index] + (before[index] - fitPositions[index]) * 0.7f + average * 0.2f;
        }
        for (size_t index = 0; relax && index < edges.size(); ++index) {
            if (cancelled(isCancelled, index)) return false;
            const auto& edge = edges[index];
            const btVector3 delta = positions[edge.second] - positions[edge.first];
            const btScalar length = delta.length();
            if (length > edge.restLength && length > 1e-6f) {
                const btVector3 correction = delta * ((length - edge.restLength) / length * 0.1f);
                positions[edge.first] += correction;
                positions[edge.second] -= correction;
            }
        }
        for (size_t index = 0; index < positions.size(); ++index) {
            if (cancelled(isCancelled, index)) return false;
            positions[index] = outsideBody(positions[index], directions[index]);
        }
        std::fill(corrections.begin(), corrections.end(), btVector3(0, 0, 0));
        std::fill(correctionCounts.begin(), correctionCounts.end(), 0);
        for (size_t faceIndex = 0; faceIndex < faces.size(); ++faceIndex) {
            if (cancelled(isCancelled, faceIndex)) return false;
            const auto& face = faces[faceIndex];
            if (!faceMayTouchBody(face)) continue;
            for (const auto& weights : faceSamples) {
                btVector3 sample(0, 0, 0);
                btVector3 outward(0, 0, 0);
                for (int corner = 0; corner < 3; ++corner) {
                    sample += positions[face[corner]] * weights[corner];
                    outward += directions[face[corner]] * weights[corner];
                }
                const btVector3 correction = outsideBody(sample, outward) - sample;
                if (correction.length2() < 1e-10f) continue;
                for (int corner = 0; corner < 3; ++corner) {
                    if (weights[corner] == 0) continue;
                    corrections[face[corner]] += correction * (weights[corner] / weights.length2());
                    correctionCounts[face[corner]] += 1;
                }
            }
        }
        movement = 0;
        for (size_t index = 0; index < positions.size(); ++index) {
            if (cancelled(isCancelled, index)) return false;
            if (correctionCounts[index] > 0) {
                positions[index] += corrections[index] / btScalar(correctionCounts[index]);
                positions[index] = outsideBody(positions[index], directions[index]);
            }
            movement = btMax(movement, (positions[index] - before[index]).length());
        }
        return true;
    }

    bool measureOverlap(WeashionClothCancellationCheck isCancelled) {
        remainingOverlap = 0;
        for (size_t index = 0; index < positions.size(); ++index) {
            if (cancelled(isCancelled, index)) return false;
            remainingOverlap = btMax(remainingOverlap, (outsideBody(positions[index], directions[index]) - positions[index]).length());
        }
        for (size_t faceIndex = 0; faceIndex < faces.size(); ++faceIndex) {
            if (cancelled(isCancelled, faceIndex)) return false;
            const auto& face = faces[faceIndex];
            if (!faceMayTouchBody(face)) continue;
            for (const auto& weights : faceSamples) {
                btVector3 sample(0, 0, 0);
                btVector3 outward(0, 0, 0);
                for (int corner = 0; corner < 3; ++corner) {
                    sample += positions[face[corner]] * weights[corner];
                    outward += directions[face[corner]] * weights[corner];
                }
                const btScalar overlap = (outsideBody(sample, outward) - sample).length();
                remainingOverlap = btMax(remainingOverlap, overlap);
            }
        }
        return true;
    }
};

extern "C" WeashionCloth *weashion_cloth_create_body(
    const float *bodyPoints, const int32_t *bandCounts, int32_t bandCount) {
    if (!bodyPoints || !bandCounts || bandCount < 1 || bandCount > 4096) return nullptr;
    try {
        auto cloth = std::make_unique<WeashionCloth>();
        int pointOffset = 0;
        for (int bandIndex = 0; bandIndex < bandCount; ++bandIndex) {
            const int count = bandCounts[bandIndex];
            if (count < 4 || count > 1024) return nullptr;
            btVector3 center(0, 0, 0);
            for (int index = 0; index < count; ++index) {
                const float *point = bodyPoints + (pointOffset + index) * 3;
                if (!std::isfinite(point[0]) || !std::isfinite(point[1]) || !std::isfinite(point[2])) return nullptr;
                center += btVector3(point[0], point[1], point[2]);
            }
            center /= btScalar(count);
            CollisionBand band;
            band.center = center;
            band.minimum = center;
            band.maximum = center;
            for (int index = 0; index < count; ++index) {
                const float *point = bodyPoints + (pointOffset + index) * 3;
                const btVector3 position(point[0], point[1], point[2]);
                band.minimum.setMin(position);
                band.maximum.setMax(position);
            }
            const btScalar margin = 0.002f;
            band.minimum -= btVector3(margin, margin, margin);
            band.maximum += btVector3(margin, margin, margin);
            btConvexHullComputer hull;
            hull.compute(bodyPoints + pointOffset * 3, sizeof(float) * 3, count, 0, 0);
            for (int faceIndex = 0; faceIndex < hull.faces.size(); ++faceIndex) {
                const auto *firstEdge = &hull.edges[hull.faces[faceIndex]];
                const auto *edge = firstEdge;
                const btVector3 origin = hull.vertices[firstEdge->getSourceVertex()];
                btVector3 normal(0, 0, 0);
                do {
                    normal += (hull.vertices[edge->getSourceVertex()] - origin).cross(
                        hull.vertices[edge->getTargetVertex()] - origin);
                    edge = edge->getNextEdgeOfFace();
                } while (edge != firstEdge);
                if (!finiteVector(normal) || normal.fuzzyZero()) continue;
                normal.normalize();
                if (normal.dot(center - origin) > 0) normal = -normal;
                btScalar offset = -SIMD_INFINITY;
                for (int index = 0; index < count; ++index) {
                    const float *point = bodyPoints + (pointOffset + index) * 3;
                    offset = btMax(offset, normal.dot(btVector3(point[0], point[1], point[2])));
                }
                if (!finiteVector(normal) || !std::isfinite(offset)) return nullptr;
                band.planes.push_back({normal, offset + margin});
            }
            if (band.planes.size() < 4) return nullptr;
            cloth->bands.push_back(std::move(band));
            pointOffset += count;
        }
        std::sort(cloth->bands.begin(), cloth->bands.end(), [](const CollisionBand& first, const CollisionBand& second) {
            return first.minimum.y() < second.minimum.y();
        });
        cloth->indexBody();
        return cloth.release();
    } catch (...) {
        return nullptr;
    }
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
        cloth->neighbors.resize(vertexCount);
        cloth->corrections.resize(vertexCount);
        cloth->correctionCounts.resize(vertexCount);
        std::unordered_set<uint64_t> connected;
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
                cloth->directions[start] += normal;
                if (connected.insert(edgeKey(start, end)).second) {
                    cloth->edges.push_back({start, end, (cloth->positions[start] - cloth->positions[end]).length()});
                    cloth->neighbors[start].push_back(end);
                    cloth->neighbors[end].push_back(start);
                }
            }
        }
        for (int index = 0; index < vertexCount; ++index) {
            const auto& point = cloth->restPositions[index];
            const btVector3 fallback = directionOr(btVector3(point.x(), 0, point.z()), btVector3(0, 1, 0));
            cloth->directions[index] = directionOr(cloth->directions[index], fallback);
        }
        cloth->positions = cloth->fitPositions;
        return 1;
    } catch (...) {
        cloth->clearGarment();
        return 0;
    }
}

extern "C" void weashion_cloth_clear_garment(WeashionCloth *cloth) {
    if (cloth) cloth->clearGarment();
}

extern "C" int32_t weashion_cloth_step(WeashionCloth *cloth, int32_t steps, WeashionClothCancellationCheck isCancelled) {
    if (!cloth || cloth->positions.empty()) return 0;
    if (cancelled(isCancelled, 0)) return -1;
    if (cloth->completedSteps >= 12) return 2;
    for (int step = 0; step < std::min(std::max(int(steps), 1), 8); ++step) {
        btScalar movement = 0;
        if (!cloth->fitPass(movement, isCancelled)) return -1;
        for (const auto& position : cloth->positions) {
            if (!finiteVector(position)) return 0;
        }
        cloth->completedSteps += 1;
        if (movement < 0.0005f || cloth->completedSteps >= 12) {
            for (int pass = 0; pass < 8; ++pass) {
                if (!cloth->fitPass(movement, isCancelled, false)) return -1;
                if (movement < 0.0001f) break;
            }
            for (const auto& position : cloth->positions) {
                if (!finiteVector(position)) return 0;
            }
            cloth->completedSteps = 12;
            if (!cloth->measureOverlap(isCancelled)) return -1;
            return std::isfinite(cloth->remainingOverlap) ? 2 : 0;
        }
    }
    return 1;
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

extern "C" float weashion_cloth_max_strain(const WeashionCloth *cloth) {
    if (!cloth) return 0;
    btScalar strain = 0;
    for (const auto& edge : cloth->edges) {
        if (edge.restLength < 0.008f) continue;
        const btScalar length = (cloth->positions[edge.first] - cloth->positions[edge.second]).length();
        strain = btMax(strain, length / edge.restLength - 1);
    }
    return strain;
}

extern "C" float weashion_cloth_remaining_overlap(const WeashionCloth *cloth) {
    return cloth ? cloth->remainingOverlap : 0;
}

extern "C" void weashion_cloth_destroy(WeashionCloth *cloth) {
    delete cloth;
}