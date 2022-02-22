/**
Linear algebra: vectors and matrices.

Copyright: Vadim Lopatin 2015-2016, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.core.linalg;

nothrow @safe:

import std.math : cos, sin, sqrt, tan, isFinite, PI;
import std.string : format;
import beamui.core.math;

/// 2-4-dimensional vector
struct Vector(T, int N) if (2 <= N && N <= 4) {
nothrow:
    union {
        T[N] vec = 0;
        struct {
            T x;
            T y;
            static if (N >= 3)
                T z;
            static if (N == 4)
                T w;
        }
    }

    alias u = x;
    alias v = y;

    /// Vector dimension number
    enum int dimension = N;

    /// Returns a pointer to the first vector element
    const(T*) ptr() const @trusted {
        return vec.ptr;
    }

    /// Create with all components filled with specified value
    this(T v) {
        vec[] = v;
    }

    this(Args...)(Args values) if (2 <= Args.length && Args.length <= N) {
        static foreach (Arg; Args)
            static assert(is(Arg : T), "Arguments must be convertible to the base vector type");
        static foreach (i; 0 .. Args.length)
            vec[i] = values[i];
    }

    this(const ref T[N] v) {
        vec = v;
    }

    this(const T[] v) {
        vec = v[0 .. N];
    }

    static if (N == 4) {
        this(Vector!(T, 3) v) {
            vec[0 .. 3] = v.vec[];
            vec[3] = 1;
        }

        ref Vector opAssign(Vector!(T, 3) v) {
            vec[0 .. 3] = v.vec[];
            vec[3] = 1;
            return this;
        }
    }

    ref Vector opAssign(T[N] v) {
        vec = v;
        return this;
    }

    /// Fill all components of vector with specified value
    ref Vector clear(T v) {
        vec[] = v;
        return this;
    }

    static if (N == 2) {
        /// Returns 2D vector rotated 90 degrees CW if left-handed, CCW if right-handed
        Vector rotated90fromXtoY() const {
            return Vector(-y, x);
        }
        /// Returns 2D vector rotated 90 degrees CCW if left-handed, CW if right-handed
        Vector rotated90fromYtoX() const {
            return Vector(y, -x);
        }
    }

    /// Returns vector with all components which are negative of components for this vector
    Vector opUnary(string op : "-")() const {
        static if (N == 2) {
            return Vector(-x, -y);
        } else {
            Vector ret = this;
            ret.vec[] *= -1;
            return ret;
        }
    }

    /// Perform operation with value to all components of vector
    ref Vector opOpAssign(string op)(T v) if (op == "+" || op == "-" || op == "*" || op == "/") {
        static if (N == 2) {
            mixin("x" ~ op ~ "= v;");
            mixin("y" ~ op ~ "= v;");
        } else
            mixin("vec[]" ~ op ~ "= v;");
        return this;
    }
    /// ditto
    Vector opBinary(string op)(T v) const if (op == "+" || op == "-" || op == "*" || op == "/") {
        Vector ret = this;
        static if (N == 2) {
            mixin("ret.x" ~ op ~ "= v;");
            mixin("ret.y" ~ op ~ "= v;");
        } else
            mixin("ret.vec[]" ~ op ~ "= v;");
        return ret;
    }

    /// Perform operation with another vector by component
    ref Vector opOpAssign(string op)(const Vector v) if (op == "+" || op == "-" || op == "*" || op == "/") {
        static if (N == 2) {
            mixin("x" ~ op ~ "= v.x;");
            mixin("y" ~ op ~ "= v.y;");
        } else
            mixin("vec[]" ~ op ~ "= v.vec[];");
        return this;
    }
    /// ditto
    Vector opBinary(string op)(const Vector v) const if (op == "+" || op == "-") {
        Vector ret = this;
        static if (N == 2) {
            mixin("ret.x" ~ op ~ "= v.x;");
            mixin("ret.y" ~ op ~ "= v.y;");
        } else
            mixin("ret.vec[]" ~ op ~ "= v.vec[];");
        return ret;
    }

    /// Dot product (sum of by-component products of vector components)
    T opBinary(string op : "*")(const Vector v) const {
        return dotProduct(this, v);
    }

    /// Sum of squares of all vector components
    T magnitudeSquared() const {
        T ret = 0;
        static foreach (i; 0 .. N)
            ret += vec[i] * vec[i];
        return ret;
    }
    /// Length of vector
    T magnitude() const {
        static if (is(T == float) || is(T == double) || is(T == real))
            return sqrt(magnitudeSquared);
        else
            return cast(T)sqrt(cast(real)magnitudeSquared);
    }
    /// ditto
    alias length = magnitude;

    /// Normalize vector: make its length == 1
    void normalize() {
        this /= length;
    }
    /// Returns normalized copy of this vector
    Vector normalized() const {
        return this / length;
    }

    int opCmp(const ref Vector b) const {
        static foreach (i; 0 .. N) {
            if (vec[i] < b.vec[i])
                return -1;
            else if (vec[i] > b.vec[i])
                return 1;
        }
        return 0; // equal
    }

    string toString() const {
        try {
            static if (N == 2)
                return format("(%s, %s)", x, y);
            static if (N == 3)
                return format("(%s, %s, %s)", x, y, z);
            static if (N == 4)
                return format("(%s, %s, %s, %s)", x, y, z, w);
        } catch (Exception e) {
            return null;
        }
    }
}

/// Dot product (sum of by-component products of vector components)
T dotProduct(T, int N)(Vector!(T, N) a, Vector!(T, N) b) {
    T ret = 0;
    static foreach (i; 0 .. N)
        ret += a.vec[i] * b.vec[i];
    return ret;
}
/// Cross product of two Vec2 is a scalar in Z axis
T crossProduct(T)(Vector!(T, 2) a, Vector!(T, 2) b) {
    return a.x * b.y - a.y * b.x;
}
/// 3D cross product
Vector!(T, 3) crossProduct(T)(Vector!(T, 3) a, Vector!(T, 3) b) {
    return Vector!(T, 3)(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);
}

alias Vec2 = Vector!(float, 2);
alias Vec3 = Vector!(float, 3);
alias Vec4 = Vector!(float, 4);

alias Vec2d = Vector!(double, 2);
alias Vec3d = Vector!(double, 3);
alias Vec4d = Vector!(double, 4);

alias Vec2i = Vector!(int, 2);
alias Vec3i = Vector!(int, 3);
alias Vec4i = Vector!(int, 4);

/** Row-major 2x3 floating point matrix, used for 2D affine transformations. Zero by default.

    Multiplication and inversion are performed as 3x3 with implicit (0,0,1) last row.
*/
struct Mat2x3 {
nothrow:
    float[3][2] store = [[0.0f, 0.0f, 0.0f], [0.0f, 0.0f, 0.0f]];

    /** Returns the pointer to the stored values array.

        Note: Values are stored in row-major order, so when passing it to OpenGL
        with `glUniform*` functions, you'll need to set `transpose` parameter to GL_TRUE.
    */
    const(float*) ptr() const return @trusted {
        return store.ptr.ptr;
    }

    this(float diagonal) {
        store[0][0] = diagonal;
        store[1][1] = diagonal;
    }

    this(ref const float[6] array) {
        store[0] = array[0 .. 3];
        store[1] = array[3 .. 6];
    }

    this(const float[] array) {
        store[0] = array[0 .. 3];
        store[1] = array[3 .. 6];
    }

    /// Identity matrix
    enum Mat2x3 identity = Mat2x3(1.0f);

    /// Add or subtract a matrix
    ref Mat2x3 opOpAssign(string op)(Mat2x3 mat) if (op == "+" || op == "-")
    out (; isFinite(), msgNotFinite) {
        mixin("store[0]" ~ op ~ "= mat.store[0];");
        mixin("store[1]" ~ op ~ "= mat.store[1];");
        return this;
    }
    /// ditto
    Mat2x3 opBinary(string op)(Mat2x3 mat) const if (op == "+" || op == "-")
    out (; isFinite(), msgNotFinite) {
        Mat2x3 ret = this;
        mixin("ret.store[0]" ~ op ~ "= mat.store[0];");
        mixin("ret.store[1]" ~ op ~ "= mat.store[1];");
        return ret;
    }
    /// Multiply this matrix by another one, as they were 3x3 with (0,0,1) last row
    ref Mat2x3 opOpAssign(string op : "*")(Mat2x3 mat)
    out (; isFinite(), msgNotFinite) {
        const a00 = store[0][0];
        const a01 = store[0][1];
        const a10 = store[1][0];
        const a11 = store[1][1];
        store[0][0] = a00 * mat.store[0][0] + a01 * mat.store[1][0];
        store[0][1] = a00 * mat.store[0][1] + a01 * mat.store[1][1];
        store[0][2] += a00 * mat.store[0][2] + a01 * mat.store[1][2];
        store[1][0] = a10 * mat.store[0][0] + a11 * mat.store[1][0];
        store[1][1] = a10 * mat.store[0][1] + a11 * mat.store[1][1];
        store[1][2] += a10 * mat.store[0][2] + a11 * mat.store[1][2];
        return this;
    }
    /// ditto
    Mat2x3 opBinary(string op : "*")(Mat2x3 mat) const
    out (; isFinite(), msgNotFinite) {
        Mat2x3 ret = void;
        ret.store[0][0] = store[0][0] * mat.store[0][0] + store[0][1] * mat.store[1][0];
        ret.store[0][1] = store[0][0] * mat.store[0][1] + store[0][1] * mat.store[1][1];
        ret.store[0][2] = store[0][0] * mat.store[0][2] + store[0][1] * mat.store[1][2] + store[0][2];
        ret.store[1][0] = store[1][0] * mat.store[0][0] + store[1][1] * mat.store[1][0];
        ret.store[1][1] = store[1][0] * mat.store[0][1] + store[1][1] * mat.store[1][1];
        ret.store[1][2] = store[1][0] * mat.store[0][2] + store[1][1] * mat.store[1][2] + store[1][2];
        return ret;
    }

    /// Transform a vector by this matrix
    Vec2 opBinary(string op : "*")(Vec2 vec) const
    out (v; .isFinite(v.x) && .isFinite(v.y), "Transformed vector is not finite") {
        const x = store[0][0] * vec.x + store[0][1] * vec.y + store[0][2];
        const y = store[1][0] * vec.x + store[1][1] * vec.y + store[1][2];
        return Vec2(x, y);
    }

    bool opEquals()(auto ref const Mat2x3 m) const {
        // dfmt off
        return
            fequal6(store[0][0], m.store[0][0]) &&
            fequal6(store[0][1], m.store[0][1]) &&
            fequal6(store[0][2], m.store[0][2]) &&
            fequal6(store[1][0], m.store[1][0]) &&
            fequal6(store[1][1], m.store[1][1]) &&
            fequal6(store[1][2], m.store[1][2]);
        // dfmt on
    }

    /// Invert this transform. If matrix is not invertible, resets it to identity matrix
    ref Mat2x3 invert() return {
        const float det = store[0][0] * store[1][1] - store[0][1] * store[1][0];
        if (fzero6(det)) {
            this = identity;
        } else {
            const invdet = 1.0f / det;
            const a00 = store[0][0];
            const a01 = store[0][1];
            const a02 = store[0][2];
            const a10 = store[1][0];
            const a11 = store[1][1];
            const a12 = store[1][2];
            store[0][0] = a11 * invdet;
            store[0][1] = -a01 * invdet;
            store[0][2] = (a01 * a12 - a02 * a11) * invdet;
            store[1][0] = -a10 * invdet;
            store[1][1] = a00 * invdet;
            store[1][2] = (a10 * a02 - a00 * a12) * invdet;
        }
        return this;
    }
    /// Returns inverted matrix. If matrix is not invertible, returns identity matrix
    Mat2x3 inverted() const {
        Mat2x3 m = this;
        return m.invert();
    }

    /// Apply translation to this matrix
    ref Mat2x3 translate(Vec2 offset) return
    out (; isFinite(), msgNotFinite) {
        store[0][2] += store[0][0] * offset.x + store[0][1] * offset.y;
        store[1][2] += store[1][0] * offset.x + store[1][1] * offset.y;
        return this;
    }
    /// Make a translation matrix
    static Mat2x3 translation(Vec2 offset)
    out (m; m.isFinite(), msgNotFinite) {
        Mat2x3 m = identity;
        m.store[0][2] = offset.x;
        m.store[1][2] = offset.y;
        return m;
    }

    /// Apply rotation to this matrix
    ref Mat2x3 rotate(float radians) return
    out (; isFinite(), msgNotFinite) {
        const c = cos(radians);
        const s = sin(radians);
        const a00 = store[0][0];
        const a10 = store[1][0];
        store[0][0] = a00 * c + store[0][1] * s;
        store[0][1] = -a00 * s + store[0][1] * c;
        store[1][0] = a10 * c + store[1][1] * s;
        store[1][1] = -a10 * s + store[1][1] * c;
        return this;
    }
    /// Make a rotation matrix
    static Mat2x3 rotation(float radians)
    out (m; m.isFinite(), msgNotFinite) {
        Mat2x3 m;
        const c = cos(radians);
        const s = sin(radians);
        m.store[0][0] = c;
        m.store[0][1] = -s;
        m.store[1][0] = s;
        m.store[1][1] = c;
        return m;
    }

    /// Apply scaling to this matrix
    ref Mat2x3 scale(Vec2 factor) return
    out (; isFinite(), msgNotFinite) {
        store[0][0] *= factor.x;
        store[1][0] *= factor.x;
        store[0][1] *= factor.y;
        store[1][1] *= factor.y;
        return this;
    }
    /// Make a scaling matrix
    static Mat2x3 scaling(Vec2 factor)
    out (m; m.isFinite(), msgNotFinite) {
        Mat2x3 m;
        m.store[0][0] = factor.x;
        m.store[1][1] = factor.y;
        return m;
    }

    /// Apply skewing to this matrix
    ref Mat2x3 skew(Vec2 factor) return
    out (; isFinite(), msgNotFinite) {
        const a = tan(factor.x);
        const b = tan(factor.y);
        const a00 = store[0][0];
        const a10 = store[1][0];
        store[0][0] += b * store[0][1];
        store[0][1] += a * a00;
        store[1][0] += b * store[1][1];
        store[1][1] += a * a10;
        return this;
    }
    /// Make a skewing matrix
    static Mat2x3 skewing(Vec2 factor)
    out (m; m.isFinite(), msgNotFinite) {
        Mat2x3 m = identity;
        m.store[0][1] = tan(factor.x);
        m.store[1][0] = tan(factor.y);
        return m;
    }

    string toString() const {
        // dfmt off
        try
            return format("[%s %s %s] [%s %s %s]",
                store[0][0], store[0][1], store[0][2],
                store[1][0], store[1][1], store[1][2]);
        catch (Exception e)
            return null;
        // dfmt on
    }

    private bool isFinite() const {
        return .isFinite((this * Vec2(1, 1)).magnitudeSquared);
    }

    static private immutable msgNotFinite = "Transformation is not finite anymore";
}

/** Row-major 4x4 floating point matrix. Zero by default.
*/
struct Mat4x4 {
nothrow:
    float[16] m = 0;

    this(float diagonal) {
        setDiagonal(diagonal);
    }

    this(const float[16] v) {
        m[] = v[];
    }

    /// Identity matrix
    enum Mat4x4 identity = Mat4x4(1.0f);

    /// Set to diagonal: fill all items of matrix with zero except main diagonal items which will be assigned to v
    ref Mat4x4 setDiagonal(float v) return {
        foreach (x; 0 .. 4)
            foreach (y; 0 .. 4)
                m[y * 4 + x] = (x == y) ? v : 0;
        return this;
    }
    /// Fill all items of matrix with specified value
    ref Mat4x4 fill(float v) return {
        m[] = v;
        return this;
    }

    ref Mat4x4 opAssign(const ref Mat4x4 v) return {
        m[] = v.m[];
        return this;
    }

    ref Mat4x4 opAssign(const Mat4x4 v) return {
        m[] = v.m[];
        return this;
    }

    ref Mat4x4 opAssign(const float[16] v) return {
        m[] = v[];
        return this;
    }

    void setOrtho(float left, float right, float bottom, float top, float nearPlane, float farPlane) {
        // Bail out if the projection volume is zero-sized.
        if (left == right || bottom == top || nearPlane == farPlane)
            return;

        // Construct the projection.
        const width = right - left;
        const invheight = top - bottom;
        const clip = farPlane - nearPlane;
        m[0 * 4 + 0] = 2.0f / width;
        m[1 * 4 + 0] = 0.0f;
        m[2 * 4 + 0] = 0.0f;
        m[3 * 4 + 0] = -(left + right) / width;
        m[0 * 4 + 1] = 0.0f;
        m[1 * 4 + 1] = 2.0f / invheight;
        m[2 * 4 + 1] = 0.0f;
        m[3 * 4 + 1] = -(top + bottom) / invheight;
        m[0 * 4 + 2] = 0.0f;
        m[1 * 4 + 2] = 0.0f;
        m[2 * 4 + 2] = -2.0f / clip;
        m[3 * 4 + 2] = -(nearPlane + farPlane) / clip;
        m[0 * 4 + 3] = 0.0f;
        m[1 * 4 + 3] = 0.0f;
        m[2 * 4 + 3] = 0.0f;
        m[3 * 4 + 3] = 1.0f;
    }

    void setPerspective(float angle, float aspect, float nearPlane, float farPlane) {
        // Bail out if the projection volume is zero-sized.
        const radians = (angle / 2.0f) * PI / 180.0f;
        if (nearPlane == farPlane || aspect == 0.0f || radians < 0.0001f)
            return;
        const f = 1 / tan(radians);
        const d = 1 / (nearPlane - farPlane);

        // Construct the projection.
        m[0 * 4 + 0] = f / aspect;
        m[1 * 4 + 0] = 0.0f;
        m[2 * 4 + 0] = 0.0f;
        m[3 * 4 + 0] = 0.0f;

        m[0 * 4 + 1] = 0.0f;
        m[1 * 4 + 1] = f;
        m[2 * 4 + 1] = 0.0f;
        m[3 * 4 + 1] = 0.0f;

        m[0 * 4 + 2] = 0.0f;
        m[1 * 4 + 2] = 0.0f;
        m[2 * 4 + 2] = (nearPlane + farPlane) * d;
        m[3 * 4 + 2] = 2.0f * nearPlane * farPlane * d;

        m[0 * 4 + 3] = 0.0f;
        m[1 * 4 + 3] = 0.0f;
        m[2 * 4 + 3] = -1.0f;
        m[3 * 4 + 3] = 0.0f;
    }

    ref Mat4x4 lookAt(const Vec3 eye, const Vec3 center, const Vec3 up) return {
        const Vec3 forward = (center - eye).normalized();
        const Vec3 side = crossProduct(forward, up).normalized();
        const Vec3 upVector = crossProduct(side, forward);

        Mat4x4 m = Mat4x4.identity;
        m[0 * 4 + 0] = side.x;
        m[1 * 4 + 0] = side.y;
        m[2 * 4 + 0] = side.z;
        m[3 * 4 + 0] = 0.0f;
        m[0 * 4 + 1] = upVector.x;
        m[1 * 4 + 1] = upVector.y;
        m[2 * 4 + 1] = upVector.z;
        m[3 * 4 + 1] = 0.0f;
        m[0 * 4 + 2] = -forward.x;
        m[1 * 4 + 2] = -forward.y;
        m[2 * 4 + 2] = -forward.z;
        m[3 * 4 + 2] = 0.0f;
        m[0 * 4 + 3] = 0.0f;
        m[1 * 4 + 3] = 0.0f;
        m[2 * 4 + 3] = 0.0f;
        m[3 * 4 + 3] = 1.0f;

        this *= m;
        translate(-eye);
        return this;
    }

    /// Transpose matrix
    void transpose() {
        // dfmt off
        const float[16] tmp = [
            m[0], m[4], m[8], m[12],
            m[1], m[5], m[9], m[13],
            m[2], m[6], m[10], m[14],
            m[3], m[7], m[11], m[15],
        ];
        // dfmt on
        m = tmp;
    }

    Mat4x4 invert() const {
        const a0 = m[0] * m[5] - m[1] * m[4];
        const a1 = m[0] * m[6] - m[2] * m[4];
        const a2 = m[0] * m[7] - m[3] * m[4];
        const a3 = m[1] * m[6] - m[2] * m[5];
        const a4 = m[1] * m[7] - m[3] * m[5];
        const a5 = m[2] * m[7] - m[3] * m[6];
        const b0 = m[8] * m[13] - m[9] * m[12];
        const b1 = m[8] * m[14] - m[10] * m[12];
        const b2 = m[8] * m[15] - m[11] * m[12];
        const b3 = m[9] * m[14] - m[10] * m[13];
        const b4 = m[9] * m[15] - m[11] * m[13];
        const b5 = m[10] * m[15] - m[11] * m[14];

        // Calculate the determinant.
        const det = a0 * b5 - a1 * b4 + a2 * b3 + a3 * b2 - a4 * b1 + a5 * b0;

        Mat4x4 inverse;

        // Close to zero, can't invert.
        if (fzero6(det))
            return inverse;

        // Support the case where m == dst.
        inverse.m[0] = m[5] * b5 - m[6] * b4 + m[7] * b3;
        inverse.m[1] = -m[1] * b5 + m[2] * b4 - m[3] * b3;
        inverse.m[2] = m[13] * a5 - m[14] * a4 + m[15] * a3;
        inverse.m[3] = -m[9] * a5 + m[10] * a4 - m[11] * a3;

        inverse.m[4] = -m[4] * b5 + m[6] * b2 - m[7] * b1;
        inverse.m[5] = m[0] * b5 - m[2] * b2 + m[3] * b1;
        inverse.m[6] = -m[12] * a5 + m[14] * a2 - m[15] * a1;
        inverse.m[7] = m[8] * a5 - m[10] * a2 + m[11] * a1;

        inverse.m[8] = m[4] * b4 - m[5] * b2 + m[7] * b0;
        inverse.m[9] = -m[0] * b4 + m[1] * b2 - m[3] * b0;
        inverse.m[10] = m[12] * a4 - m[13] * a2 + m[15] * a0;
        inverse.m[11] = -m[8] * a4 + m[9] * a2 - m[11] * a0;

        inverse.m[12] = -m[4] * b3 + m[5] * b1 - m[6] * b0;
        inverse.m[13] = m[0] * b3 - m[1] * b1 + m[2] * b0;
        inverse.m[14] = -m[12] * a3 + m[13] * a1 - m[14] * a0;
        inverse.m[15] = m[8] * a3 - m[9] * a1 + m[10] * a0;

        const mul = 1.0f / det;
        inverse *= mul;
        return inverse;
    }

    ref Mat4x4 setLookAt(const Vec3 eye, const Vec3 center, const Vec3 up) return {
        this = Mat4x4.identity;
        lookAt(eye, center, up);
        return this;
    }

    /// Perform operation with a scalar to all items of matrix
    void opOpAssign(string op)(float v) if (op == "+" || op == "-" || op == "*" || op == "/") {
        mixin("m[]" ~ op ~ "= v;");
    }
    /// ditto
    Mat4x4 opBinary(string op)(float v) const if (op == "+" || op == "-" || op == "*" || op == "/") {
        Mat4x4 ret = this;
        mixin("ret.m[]" ~ op ~ "= v;");
        return ret;
    }

    /// Multiply this matrix by another matrix
    Mat4x4 opBinary(string op : "*")(const ref Mat4x4 b) const {
        return mul(this, b);
    }
    /// ditto
    void opOpAssign(string op : "*")(const ref Mat4x4 b) {
        this = mul(this, b);
    }

    /// Multiply two matrices
    static Mat4x4 mul(const ref Mat4x4 a, const ref Mat4x4 b) {
        Mat4x4 m = void;
        // dfmt off
        m.m[0 * 4 + 0] = a.m[0 * 4 + 0] * b.m[0 * 4 + 0] + a.m[1 * 4 + 0] * b.m[0 * 4 + 1] + a.m[2 * 4 + 0] * b.m[0 * 4 + 2] + a.m[3 * 4 + 0] * b.m[0 * 4 + 3];
        m.m[0 * 4 + 1] = a.m[0 * 4 + 1] * b.m[0 * 4 + 0] + a.m[1 * 4 + 1] * b.m[0 * 4 + 1] + a.m[2 * 4 + 1] * b.m[0 * 4 + 2] + a.m[3 * 4 + 1] * b.m[0 * 4 + 3];
        m.m[0 * 4 + 2] = a.m[0 * 4 + 2] * b.m[0 * 4 + 0] + a.m[1 * 4 + 2] * b.m[0 * 4 + 1] + a.m[2 * 4 + 2] * b.m[0 * 4 + 2] + a.m[3 * 4 + 2] * b.m[0 * 4 + 3];
        m.m[0 * 4 + 3] = a.m[0 * 4 + 3] * b.m[0 * 4 + 0] + a.m[1 * 4 + 3] * b.m[0 * 4 + 1] + a.m[2 * 4 + 3] * b.m[0 * 4 + 2] + a.m[3 * 4 + 3] * b.m[0 * 4 + 3];
        m.m[1 * 4 + 0] = a.m[0 * 4 + 0] * b.m[1 * 4 + 0] + a.m[1 * 4 + 0] * b.m[1 * 4 + 1] + a.m[2 * 4 + 0] * b.m[1 * 4 + 2] + a.m[3 * 4 + 0] * b.m[1 * 4 + 3];
        m.m[1 * 4 + 1] = a.m[0 * 4 + 1] * b.m[1 * 4 + 0] + a.m[1 * 4 + 1] * b.m[1 * 4 + 1] + a.m[2 * 4 + 1] * b.m[1 * 4 + 2] + a.m[3 * 4 + 1] * b.m[1 * 4 + 3];
        m.m[1 * 4 + 2] = a.m[0 * 4 + 2] * b.m[1 * 4 + 0] + a.m[1 * 4 + 2] * b.m[1 * 4 + 1] + a.m[2 * 4 + 2] * b.m[1 * 4 + 2] + a.m[3 * 4 + 2] * b.m[1 * 4 + 3];
        m.m[1 * 4 + 3] = a.m[0 * 4 + 3] * b.m[1 * 4 + 0] + a.m[1 * 4 + 3] * b.m[1 * 4 + 1] + a.m[2 * 4 + 3] * b.m[1 * 4 + 2] + a.m[3 * 4 + 3] * b.m[1 * 4 + 3];
        m.m[2 * 4 + 0] = a.m[0 * 4 + 0] * b.m[2 * 4 + 0] + a.m[1 * 4 + 0] * b.m[2 * 4 + 1] + a.m[2 * 4 + 0] * b.m[2 * 4 + 2] + a.m[3 * 4 + 0] * b.m[2 * 4 + 3];
        m.m[2 * 4 + 1] = a.m[0 * 4 + 1] * b.m[2 * 4 + 0] + a.m[1 * 4 + 1] * b.m[2 * 4 + 1] + a.m[2 * 4 + 1] * b.m[2 * 4 + 2] + a.m[3 * 4 + 1] * b.m[2 * 4 + 3];
        m.m[2 * 4 + 2] = a.m[0 * 4 + 2] * b.m[2 * 4 + 0] + a.m[1 * 4 + 2] * b.m[2 * 4 + 1] + a.m[2 * 4 + 2] * b.m[2 * 4 + 2] + a.m[3 * 4 + 2] * b.m[2 * 4 + 3];
        m.m[2 * 4 + 3] = a.m[0 * 4 + 3] * b.m[2 * 4 + 0] + a.m[1 * 4 + 3] * b.m[2 * 4 + 1] + a.m[2 * 4 + 3] * b.m[2 * 4 + 2] + a.m[3 * 4 + 3] * b.m[2 * 4 + 3];
        m.m[3 * 4 + 0] = a.m[0 * 4 + 0] * b.m[3 * 4 + 0] + a.m[1 * 4 + 0] * b.m[3 * 4 + 1] + a.m[2 * 4 + 0] * b.m[3 * 4 + 2] + a.m[3 * 4 + 0] * b.m[3 * 4 + 3];
        m.m[3 * 4 + 1] = a.m[0 * 4 + 1] * b.m[3 * 4 + 0] + a.m[1 * 4 + 1] * b.m[3 * 4 + 1] + a.m[2 * 4 + 1] * b.m[3 * 4 + 2] + a.m[3 * 4 + 1] * b.m[3 * 4 + 3];
        m.m[3 * 4 + 2] = a.m[0 * 4 + 2] * b.m[3 * 4 + 0] + a.m[1 * 4 + 2] * b.m[3 * 4 + 1] + a.m[2 * 4 + 2] * b.m[3 * 4 + 2] + a.m[3 * 4 + 2] * b.m[3 * 4 + 3];
        m.m[3 * 4 + 3] = a.m[0 * 4 + 3] * b.m[3 * 4 + 0] + a.m[1 * 4 + 3] * b.m[3 * 4 + 1] + a.m[2 * 4 + 3] * b.m[3 * 4 + 2] + a.m[3 * 4 + 3] * b.m[3 * 4 + 3];
        // dfmt on
        return m;
    }

    /// Multiply matrix by Vec3
    Vec3 opBinary(string op : "*")(const Vec3 v) const {
        const x = v.x * m[0 * 4 + 0] + v.y * m[1 * 4 + 0] + v.z * m[2 * 4 + 0] + m[3 * 4 + 0];
        const y = v.x * m[0 * 4 + 1] + v.y * m[1 * 4 + 1] + v.z * m[2 * 4 + 1] + m[3 * 4 + 1];
        const z = v.x * m[0 * 4 + 2] + v.y * m[1 * 4 + 2] + v.z * m[2 * 4 + 2] + m[3 * 4 + 2];
        const w = v.x * m[0 * 4 + 3] + v.y * m[1 * 4 + 3] + v.z * m[2 * 4 + 3] + m[3 * 4 + 3];
        if (w == 1.0f)
            return Vec3(x, y, z);
        else
            return Vec3(x / w, y / w, z / w);
    }
    /// ditto
    Vec3 opBinaryRight(string op : "*")(const Vec3 v) const {
        const x = v.x * m[0 * 4 + 0] + v.y * m[0 * 4 + 1] + v.z * m[0 * 4 + 2] + m[0 * 4 + 3];
        const y = v.x * m[1 * 4 + 0] + v.y * m[1 * 4 + 1] + v.z * m[1 * 4 + 2] + m[1 * 4 + 3];
        const z = v.x * m[2 * 4 + 0] + v.y * m[2 * 4 + 1] + v.z * m[2 * 4 + 2] + m[2 * 4 + 3];
        const w = v.x * m[3 * 4 + 0] + v.y * m[3 * 4 + 1] + v.z * m[3 * 4 + 2] + m[3 * 4 + 3];
        if (w == 1.0f)
            return Vec3(x, y, z);
        else
            return Vec3(x / w, y / w, z / w);
    }

    /// Multiply matrix by Vec4
    Vec4 opBinary(string op : "*")(const Vec4 v) const {
        const x = v.x * m[0 * 4 + 0] + v.y * m[1 * 4 + 0] + v.z * m[2 * 4 + 0] + v.w * m[3 * 4 + 0];
        const y = v.x * m[0 * 4 + 1] + v.y * m[1 * 4 + 1] + v.z * m[2 * 4 + 1] + v.w * m[3 * 4 + 1];
        const z = v.x * m[0 * 4 + 2] + v.y * m[1 * 4 + 2] + v.z * m[2 * 4 + 2] + v.w * m[3 * 4 + 2];
        const w = v.x * m[0 * 4 + 3] + v.y * m[1 * 4 + 3] + v.z * m[2 * 4 + 3] + v.w * m[3 * 4 + 3];
        return Vec4(x, y, z, w);
    }
    /// ditto
    Vec4 opBinaryRight(string op : "*")(const Vec4 v) const {
        const x = v.x * m[0 * 4 + 0] + v.y * m[0 * 4 + 1] + v.z * m[0 * 4 + 2] + v.w * m[0 * 4 + 3];
        const y = v.x * m[1 * 4 + 0] + v.y * m[1 * 4 + 1] + v.z * m[1 * 4 + 2] + v.w * m[1 * 4 + 3];
        const z = v.x * m[2 * 4 + 0] + v.y * m[2 * 4 + 1] + v.z * m[2 * 4 + 2] + v.w * m[2 * 4 + 3];
        const w = v.x * m[3 * 4 + 0] + v.y * m[3 * 4 + 1] + v.z * m[3 * 4 + 2] + v.w * m[3 * 4 + 3];
        return Vec4(x, y, z, w);
    }

    /// 2d index by row, col
    ref float opIndex(int y, int x) return {
        return m[y * 4 + x];
    }

    /// 2d index by row, col
    float opIndex(int y, int x) const {
        return m[y * 4 + x];
    }

    /// Scalar index by rows then (y*4 + x)
    ref float opIndex(int index) return {
        return m[index];
    }

    /// Scalar index by rows then (y*4 + x)
    float opIndex(int index) const {
        return m[index];
    }

    ref Mat4x4 translate(const Vec3 v) return {
        m[3 * 4 + 0] += m[0 * 4 + 0] * v.x + m[1 * 4 + 0] * v.y + m[2 * 4 + 0] * v.z;
        m[3 * 4 + 1] += m[0 * 4 + 1] * v.x + m[1 * 4 + 1] * v.y + m[2 * 4 + 1] * v.z;
        m[3 * 4 + 2] += m[0 * 4 + 2] * v.x + m[1 * 4 + 2] * v.y + m[2 * 4 + 2] * v.z;
        m[3 * 4 + 3] += m[0 * 4 + 3] * v.x + m[1 * 4 + 3] * v.y + m[2 * 4 + 3] * v.z;
        return this;
    }

    ref Mat4x4 rotate(float angle, const Vec3 axis) return {
        if (angle == 0.0f)
            return this;

        float x = axis.x;
        float y = axis.y;
        float z = axis.z;

        float c, s, ic;
        if (angle == 90.0f || angle == -270.0f) {
            s = 1.0f;
            c = 0.0f;
        } else if (angle == -90.0f || angle == 270.0f) {
            s = -1.0f;
            c = 0.0f;
        } else if (angle == 180.0f || angle == -180.0f) {
            s = 0.0f;
            c = -1.0f;
        } else {
            const a = angle * PI / 180.0f;
            c = cos(a);
            s = sin(a);
        }

        Mat4x4 m;
        bool quick;
        if (x == 0.0f) {
            if (y == 0.0f) {
                if (z != 0.0f) {
                    // Rotate around the Z axis.
                    m = Mat4x4.identity;
                    m.m[0 * 4 + 0] = c;
                    m.m[1 * 4 + 1] = c;
                    if (z < 0.0f) {
                        m.m[1 * 4 + 0] = s;
                        m.m[0 * 4 + 1] = -s;
                    } else {
                        m.m[1 * 4 + 0] = -s;
                        m.m[0 * 4 + 1] = s;
                    }
                    quick = true;
                }
            } else if (z == 0.0f) {
                // Rotate around the Y axis.
                m = Mat4x4.identity;
                m.m[0 * 4 + 0] = c;
                m.m[2 * 4 + 2] = c;
                if (y < 0.0f) {
                    m.m[2 * 4 + 0] = -s;
                    m.m[0 * 4 + 2] = s;
                } else {
                    m.m[2 * 4 + 0] = s;
                    m.m[0 * 4 + 2] = -s;
                }
                quick = true;
            }
        } else if (y == 0.0f && z == 0.0f) {
            // Rotate around the X axis.
            m = Mat4x4.identity;
            m.m[1 * 4 + 1] = c;
            m.m[2 * 4 + 2] = c;
            if (x < 0.0f) {
                m.m[2 * 4 + 1] = s;
                m.m[1 * 4 + 2] = -s;
            } else {
                m.m[2 * 4 + 1] = -s;
                m.m[1 * 4 + 2] = s;
            }
            quick = true;
        }
        if (!quick) {
            float len = x * x + y * y + z * z;
            if (!fzero6(len - 1.0f) && !fzero6(len)) {
                len = sqrt(len);
                x /= len;
                y /= len;
                z /= len;
            }
            ic = 1.0f - c;
            m.m[0 * 4 + 0] = x * x * ic + c;
            m.m[1 * 4 + 0] = x * y * ic - z * s;
            m.m[2 * 4 + 0] = x * z * ic + y * s;
            m.m[3 * 4 + 0] = 0.0f;
            m.m[0 * 4 + 1] = y * x * ic + z * s;
            m.m[1 * 4 + 1] = y * y * ic + c;
            m.m[2 * 4 + 1] = y * z * ic - x * s;
            m.m[3 * 4 + 1] = 0.0f;
            m.m[0 * 4 + 2] = x * z * ic - y * s;
            m.m[1 * 4 + 2] = y * z * ic + x * s;
            m.m[2 * 4 + 2] = z * z * ic + c;
            m.m[3 * 4 + 2] = 0.0f;
            m.m[0 * 4 + 3] = 0.0f;
            m.m[1 * 4 + 3] = 0.0f;
            m.m[2 * 4 + 3] = 0.0f;
            m.m[3 * 4 + 3] = 1.0f;
        }
        this *= m;
        return this;
    }

    /// Inplace rotate around X axis
    ref Mat4x4 rotateX(float angle) return {
        return rotate(angle, Vec3(1, 0, 0));
    }
    /// Inplace rotate around Y axis
    ref Mat4x4 rotateY(float angle) return {
        return rotate(angle, Vec3(0, 1, 0));
    }
    /// Inplace rotate around Z axis
    ref Mat4x4 rotateZ(float angle) return {
        return rotate(angle, Vec3(0, 0, 1));
    }

    ref Mat4x4 scale(float v) return {
        m[0 .. 12] *= v;
        return this;
    }

    ref Mat4x4 scale(const Vec3 v) return {
        m[0 .. 4] *= v.x;
        m[4 .. 8] *= v.y;
        m[8 .. 12] *= v.z;
        return this;
    }

    /// Decomposes the scale, rotation and translation components of this matrix
    bool decompose(Vec3* scale, Vec4* rotation, Vec3* translation) const {
        if (translation) {
            // Extract the translation.
            translation.x = m[12];
            translation.y = m[13];
            translation.z = m[14];
        }

        // Nothing left to do.
        if (!scale && !rotation)
            return true;

        // Extract the scale.
        // This is simply the length of each axis (row/column) in the matrix.
        const xaxis = Vec3(m[0], m[1], m[2]);
        const scaleX = xaxis.length;

        const yaxis = Vec3(m[4], m[5], m[6]);
        const scaleY = yaxis.length;

        const zaxis = Vec3(m[8], m[9], m[10]);
        float scaleZ = zaxis.length;

        // Determine if we have a negative scale (true if determinant is less than zero).
        // In this case, we simply negate a single axis of the scale.
        const det = determinant();
        if (det < 0)
            scaleZ = -scaleZ;

        if (scale) {
            scale.x = scaleX;
            scale.y = scaleY;
            scale.z = scaleZ;
        }

        // Nothing left to do.
        if (!rotation)
            return true;

        //// Scale too close to zero, can't decompose rotation.
        //if (scaleX < MATH_TOLERANCE || scaleY < MATH_TOLERANCE || fabs(scaleZ) < MATH_TOLERANCE)
        //    return false;
        // TODO: support rotation
        return false;
    }

    float determinant() const {
        const a0 = m[0] * m[5] - m[1] * m[4];
        const a1 = m[0] * m[6] - m[2] * m[4];
        const a2 = m[0] * m[7] - m[3] * m[4];
        const a3 = m[1] * m[6] - m[2] * m[5];
        const a4 = m[1] * m[7] - m[3] * m[5];
        const a5 = m[2] * m[7] - m[3] * m[6];
        const b0 = m[8] * m[13] - m[9] * m[12];
        const b1 = m[8] * m[14] - m[10] * m[12];
        const b2 = m[8] * m[15] - m[11] * m[12];
        const b3 = m[9] * m[14] - m[10] * m[13];
        const b4 = m[9] * m[15] - m[11] * m[13];
        const b5 = m[10] * m[15] - m[11] * m[14];
        // calculate the determinant
        return a0 * b5 - a1 * b4 + a2 * b3 + a3 * b2 - a4 * b1 + a5 * b0;
    }

    Vec3 forwardVector() const {
        return Vec3(-m[8], -m[9], -m[10]);
    }

    Vec3 backVector() const {
        return Vec3(m[8], m[9], m[10]);
    }

    void transformVector(ref Vec3 v) const {
        transformVector(v.x, v.y, v.z, 0, v);
    }

    void transformPoint(ref Vec3 v) const {
        transformVector(v.x, v.y, v.z, 1, v);
    }

    void transformVector(float x, float y, float z, float w, ref Vec3 dst) const {
        dst.x = x * m[0] + y * m[4] + z * m[8] + w * m[12];
        dst.y = x * m[1] + y * m[5] + z * m[9] + w * m[13];
        dst.z = x * m[2] + y * m[6] + z * m[10] + w * m[14];
    }
}

/// Calculate normal for triangle
Vec3 triangleNormal(Vec3 p1, Vec3 p2, Vec3 p3) {
    return crossProduct(p2 - p1, p3 - p2).normalized();
}
/// ditto
Vec3 triangleNormal(ref float[3] p1, ref float[3] p2, ref float[3] p3) {
    return crossProduct(Vec3(p2) - Vec3(p1), Vec3(p3) - Vec3(p2)).normalized();
}

/** Find intersection point for two vectors with start points `p1`, `p2` and normalized directions `dir1`, `dir2`.

    Returns `p1` if vectors are parallel.
*/
Vec2 intersectVectors(Vec2 p1, Vec2 dir1, Vec2 p2, Vec2 dir2) {
    /*
    L1 = P1 + a * V1
    L2 = P2 + b * V2
    P1 + a * V1 = P2 + b * V2
    a * V1 = (P2 - P1) + b * V2
    a * (V1 x V2) = (P2 - P1) x V2
    a = ((P2 - P1) x V2) / (V1 x V2)
    return P1 + a * V1
    */
    const float d1 = crossProduct(p2 - p1, dir2);
    const float d2 = crossProduct(dir1, dir2);
    // a * d2 = d1
    if (!fzero2(d2))
        return p1 + dir1 * d1 / d2;
    else
        return p1; // parallel
}

//===============================================================
// Tests

unittest {
    Vec3 a, b, c;
    a.clear(5);
    b.clear(2);
    const d = a * b;
    const r1 = a + b;
    const r2 = a - b;
    c = a;
    c += b;
    c = a;
    c -= b;
    c = a;
    c *= b;
    c = a;
    c /= b;
    c += 0.3f;
    c -= 0.3f;
    c *= 0.3f;
    c /= 0.3f;
    a.x += 0.5f;
    a.y += 0.5f;
    a.z += 0.5f;
    const v = b.vec;
    a = [0.1f, 0.2f, 0.3f];
    a.normalize();
    c = b.normalized;
}

unittest {
    Vec4 a, b, c;
    a.clear(5);
    b.clear(2);
    const d = a * b;
    const r1 = a + b;
    const r2 = a - b;
    c = a;
    c += b;
    c = a;
    c -= b;
    c = a;
    c *= b;
    c = a;
    c /= b;
    c += 0.3f;
    c -= 0.3f;
    c *= 0.3f;
    c /= 0.3f;
    a.x += 0.5f;
    a.y += 0.5f;
    a.z += 0.5f;
    const v = b.vec;
    a = [0.1f, 0.2f, 0.3f, 0.4f];
    a.normalize();
    c = b.normalized;
}

unittest {
    const a = Vec2(10, 8);
    const b = Vec2(-5, -4);
    const c = Vec2(5, 5);
    const z = Mat2x3.init;
    const i = Mat2x3.identity;
    const t = Mat2x3.translation(Vec2(1, -1));
    const r = Mat2x3.rotation(PI / 3);
    const s = Mat2x3.scaling(Vec2(2, 3));
    const za = z * a;
    const ib = i * b;
    const ta = t * a;
    const tb = t * b;
    const rc = r * c;
    const sa = s * a;
    const sb = s * b;
    assert(fequal6(za.x, 0) && fequal6(za.y, 0));
    assert(fequal6(ib.x, -5) && fequal6(ib.y, -4));
    assert(fequal6(ta.x, 11) && fequal6(ta.y, 7));
    assert(fequal6(tb.x, -4) && fequal6(tb.y, -5));
    assert(fequal2(rc.x, -1.83) && fequal2(rc.y, 6.83));
    assert(fequal6(sa.x, 20) && fequal6(sa.y, 24));
    assert(fequal6(sb.x, -10) && fequal6(sb.y, -12));

    const m1 = t * r * s;
    const m2 = Mat2x3.identity.translate(Vec2(1, -1)).rotate(PI / 3).scale(Vec2(2, 3));
    const d1 = m1 * Vec2(15, 10);
    const d2 = m2 * Vec2(15, 10);
    assert(fequal2(d1.x, -9.98) && fequal2(d1.y, 39.98));
    assert(fequal6(d1.x, d2.x) && fequal6(d1.y, d2.y));

    assert(i * i.inverted == Mat2x3.identity);
    assert(t * t.inverted == Mat2x3.identity);
    assert(r * r.inverted == Mat2x3.identity);
    assert(s * s.inverted == Mat2x3.identity);
    assert(m1 * m1.inverted == Mat2x3.identity);
    assert(m2 * m2.inverted == Mat2x3.identity);
}

unittest {
    Mat4x4 m = Mat4x4.identity;
    m = [1.0f, 2.0f, 3.0f, 4.0f, 5.0f, 6.0f, 7.0f, 8.0f, 9.0f, 10.0f, 11.0f, 12.0f, 13.0f, 14.0f, 15.0f, 16.0f];
    float r;
    r = m[1, 3];
    m[2, 1] = 0.0f;
    m += 1;
    m -= 2;
    m *= 3;
    m /= 3;
    m.translate(Vec3(2, 3, 4));
    m.lookAt(Vec3(5, 5, 5), Vec3(0, 0, 0), Vec3(-1, 1, 1));
    m.setLookAt(Vec3(5, 5, 5), Vec3(0, 0, 0), Vec3(-1, 1, 1));
    m.scale(Vec3(2, 3, 4));

    const vv1 = Vec3(1, 2, 3);
    const p1 = m * vv1;
    const vv2 = Vec3(3, 4, 5);
    const p2 = vv2 * m;
    const p3 = Vec4(1, 2, 3, 4) * m;
    const p4 = m * Vec4(1, 2, 3, 4);

    m.rotate(30, Vec3(1, 1, 1));
    m.rotateX(10);
    m.rotateY(10);
    m.rotateZ(10);
}
