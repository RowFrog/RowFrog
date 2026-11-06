import math
import random

from rowfrog import interpolate

POINTS = [(0.0, 0.0), (2200.0, 300.0), (500.0, 2100.0), (2600.0, 2500.0), (1300.0, 4400.0), (-400.0, 3600.0)]
BOX = (-3000.0, -3000.0, 5000.0, 7000.0)


def test_weights_are_never_negative_and_add_up_to_one():
    nn = interpolate.NaturalNeighbours(POINTS, BOX)
    rnd = random.Random(1)
    for _ in range(300):
        w = nn.weights((rnd.uniform(-2500, 4500), rnd.uniform(-2500, 6500)))
        assert all(v >= 0 for v in w.values())
        assert math.isclose(sum(w.values()), 1.0)


def test_a_spot_on_a_point_gets_that_point_only():
    nn = interpolate.NaturalNeighbours(POINTS, BOX)
    assert nn.weights(POINTS[3]) == {3: 1.0}
    near = nn.weights((POINTS[3][0] + 1, POINTS[3][1]))
    assert near[3] > 0.99


def test_an_even_slope_is_reproduced_exactly_inside_the_points():
    nn = interpolate.NaturalNeighbours(POINTS, BOX)
    values = [3 + 0.001 * x - 0.0005 * y for x, y in POINTS]
    for spot in [(1200.0, 1500.0), (1500.0, 3000.0), (800.0, 900.0)]:
        assert math.isclose(interpolate.blend(nn.weights(spot), values), 3 + 0.001 * spot[0] - 0.0005 * spot[1], abs_tol=1e-6)


def test_blends_stay_between_the_lowest_and_highest_point():
    nn = interpolate.NaturalNeighbours(POINTS, BOX)
    values = [4.0, 9.5, 2.0, 7.0, 11.0, 3.0]
    rnd = random.Random(2)
    for _ in range(300):
        v = interpolate.blend(nn.weights((rnd.uniform(-2500, 4500), rnd.uniform(-2500, 6500))), values)
        assert min(values) - 1e-9 <= v <= max(values) + 1e-9


def test_visibility_blends_on_a_log_scale():
    assert math.isclose(interpolate.blend_visibility({0: 0.5, 1: 0.5}, [300.0, 15000.0]), math.sqrt(300 * 15000))


def test_direction_comes_from_the_arrows():
    assert interpolate.blend_direction({0: 0.5, 1: 0.5}, [5.0, 5.0], [350.0, 10.0]) % 360 < 1e-6 or \
        abs(interpolate.blend_direction({0: 0.5, 1: 0.5}, [5.0, 5.0], [350.0, 10.0]) - 360) < 1e-6
