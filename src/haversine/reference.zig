const asin = @import("std").math.asin;
const cos = @import("std").math.cos;
const degreesToRadians = @import("std").math.degreesToRadians;
const sin = @import("std").math.sin;
const sqrt = @import("std").math.sqrt;
const std = @import("std");

// Reference implementation https://github.com/cmuratori/computer_enhance/blob/main/perfaware/part2/listing_0065_haversine_formula.cpp#L30
pub fn haversine_ref(x0: f64, y0: f64, x1: f64, y1: f64, earth_radius: f64) f64 {
    var lat1 = y0;
    var lat2 = y1;
    const lon1 = x0;
    const lon2 = x1;

    const dLat = degreesToRadians(lat2 - lat1);
    const dLon = degreesToRadians(lon2 - lon1);
    lat1 = degreesToRadians(lat1);
    lat2 = degreesToRadians(lat2);

    const a = square(sin(dLat / 2.0)) + cos(lat1) * cos(lat2) * square(sin(dLon / 2));
    const c = 2.0 * asin(sqrt(a));

    const result = earth_radius * c;
    return result;
}

fn square(a: anytype) @TypeOf(a) {
    return a * a;
}
