mod vector

use "std:slices" as slices

pub Vec2[T](
    i0 T
    i1 T
)

Vec2[T].view() T[]:
    ret slices.fromPtr(addrof this.i0, 2)
..

pub Vec3[T](
    i0 T
    i1 T
    i2 T
)

Vec3[T].view() T[]:
    ret slices.fromPtr(addrof this.i0, 3)
..

pub Vec4[T](
    i0 T
    i1 T
    i2 T
    i3 T
)

Vec4[T].view() T[]:
    ret slices.fromPtr(addrof this.i0, 4)
..
