"""
Arclight Overcast — Black Hole Transport Atlas Generator
=========================================================
Precomputes the full optical transport field for a Schwarzschild black hole.

Each ray from the camera is traced through curved spacetime. The geodesic
is integrated in the ray's own orbital plane (2D), then lifted back to 3D
to find disk intersections against the equatorial plane.

Outputs 4 packed RGBA float16 maps per view slice.

Reference: arXiv:2010.08735 (Bruneton)
Geodesic equation: d²u/dφ² = 1.5u² - u  (Binet form, Schwarzschild, r_s = 1)
"""

import numpy as np
from pathlib import Path
import json
import sys

# ---------------------------------------------------------------------------
# Constants (Schwarzschild units: r_s = 1, G = M = c = 1)
# ---------------------------------------------------------------------------

MU = 4.0 / 27.0           # critical e² at photon sphere
DISK_INNER = 3.0           # ISCO
DISK_OUTER = 12.0
RESOLUTION = 1024


# ---------------------------------------------------------------------------
# Geodesic integrator (Binet equation, RK4)
# ---------------------------------------------------------------------------

def integrate_geodesic(u0, u_dot0, dphi=0.0005, max_steps=50000):
    """
    Integrate d²u/dφ² = 1.5u² - u from initial (u, u_dot).
    Returns (phis, us, u_dots) arrays. Stops on escape (u<=0) or capture (u>=1).
    """
    u, ud = u0, u_dot0
    phi = 0.0
    phis, us, uds = [phi], [u], [ud]

    for _ in range(max_steps):
        # RK4
        def f(u_v, ud_v):
            return ud_v, 1.5 * u_v * u_v - u_v

        k1u, k1d = f(u, ud)
        k2u, k2d = f(u + 0.5*dphi*k1u, ud + 0.5*dphi*k1d)
        k3u, k3d = f(u + 0.5*dphi*k2u, ud + 0.5*dphi*k2d)
        k4u, k4d = f(u + dphi*k3u, ud + dphi*k3d)

        u  += dphi * (k1u + 2*k2u + 2*k3u + k4u) / 6
        ud += dphi * (k1d + 2*k2d + 2*k3d + k4d) / 6
        phi += dphi

        if u <= 0 or u >= 1.0:
            break

        phis.append(phi)
        us.append(u)
        uds.append(ud)

    return np.array(phis), np.array(us), np.array(uds)


# ---------------------------------------------------------------------------
# 3D ray geometry
# ---------------------------------------------------------------------------

def normalize(v):
    n = np.linalg.norm(v)
    return v / n if n > 1e-12 else v


def build_orbital_basis(cam_pos, ray_dir):
    """
    Build an orthonormal basis for the ray's orbital plane.

    In Schwarzschild spacetime, each photon orbit lies in a plane through the
    origin defined by (cam_pos, ray_dir). We construct:
      e1 = radial direction (from origin toward camera)
      e2 = perpendicular to e1 in the orbital plane
      normal = e1 × e2 (perpendicular to orbital plane)

    The geodesic (r, φ) maps to 3D as: pos = r * (cos φ * e1 + sin φ * e2)
    where φ=0 is the camera's radial direction.
    """
    r_hat = normalize(cam_pos)

    # Component of ray_dir perpendicular to radial
    perp = ray_dir - np.dot(ray_dir, r_hat) * r_hat
    perp_norm = np.linalg.norm(perp)

    if perp_norm < 1e-12:
        # Ray is exactly radial — pick arbitrary perpendicular
        if abs(r_hat[1]) < 0.9:
            perp = np.cross(r_hat, np.array([0, 1, 0]))
        else:
            perp = np.cross(r_hat, np.array([1, 0, 0]))
        perp = normalize(perp)
    else:
        perp = perp / perp_norm

    e1 = r_hat
    e2 = perp
    normal = np.cross(e1, e2)

    return e1, e2, normal


def orbital_to_3d(r, phi, e1, e2):
    """Convert (r, φ) in the orbital plane to 3D coordinates."""
    return r * (np.cos(phi) * e1 + np.sin(phi) * e2)


# ---------------------------------------------------------------------------
# Ray initial conditions
# ---------------------------------------------------------------------------

def ray_initial_conditions(cam_pos, ray_dir):
    """
    Compute Schwarzschild geodesic initial conditions from 3D camera ray.

    Returns (u_cam, u_dot_cam, e_sq, delta) where:
      u = 1/r
      u_dot = du/dφ
      e² = u_dot² + u²(1-u)  (conserved)
      delta = angle between ray and radial at camera
    """
    r_cam = np.linalg.norm(cam_pos)
    u_cam = 1.0 / r_cam
    r_hat = cam_pos / r_cam

    # delta measured from INWARD radial: cos_delta > 0 means ray has inward component
    cos_delta = -np.dot(ray_dir, r_hat)
    sin_delta = np.sqrt(max(0, 1.0 - cos_delta**2))
    delta = np.arccos(np.clip(cos_delta, -1, 1))

    if sin_delta < 1e-12:
        u_dot = u_cam * 100.0 if cos_delta > 0 else -u_cam * 100.0
    else:
        # u_dot > 0 for inward rays (u increases = r decreases)
        u_dot = u_cam * cos_delta / sin_delta

    e_sq = u_dot**2 + u_cam**2 * (1.0 - u_cam)

    return u_cam, u_dot, e_sq, delta


# ---------------------------------------------------------------------------
# Disk intersection
# ---------------------------------------------------------------------------

def find_disk_crossings(phis, us, e1, e2, disk_up=np.array([0, 1, 0])):
    """
    Find where the ray path in 3D crosses the disk plane (equatorial, y=0).

    For each crossing within [DISK_INNER, DISK_OUTER], computes disk UV
    and Doppler factor.
    """
    crossings = []

    for i in range(1, len(phis)):
        u_prev, u_curr = us[i-1], us[i]
        if u_prev < 1e-10 or u_curr < 1e-10:
            continue

        r_prev = 1.0 / u_prev
        r_curr = 1.0 / u_curr
        phi_prev = phis[i-1]
        phi_curr = phis[i]

        # 3D positions along the geodesic
        p_prev = orbital_to_3d(r_prev, phi_prev, e1, e2)
        p_curr = orbital_to_3d(r_curr, phi_curr, e1, e2)

        y_prev = np.dot(p_prev, disk_up)
        y_curr = np.dot(p_curr, disk_up)

        # Check for equatorial plane crossing
        if y_prev * y_curr >= 0:
            continue

        # Interpolate to crossing
        t = abs(y_prev) / max(abs(y_curr - y_prev), 1e-12)
        p_cross = p_prev + t * (p_curr - p_prev)
        r_cross = np.linalg.norm(p_cross)

        if r_cross < DISK_INNER or r_cross > DISK_OUTER:
            continue

        # Disk UV (polar coordinates in the equatorial plane)
        # Project crossing point onto the disk plane
        p_disk = p_cross - np.dot(p_cross, disk_up) * disk_up
        disk_phi = np.arctan2(p_disk[2], p_disk[0])  # azimuthal angle
        if disk_phi < 0:
            disk_phi += 2 * np.pi

        disk_r_norm = (r_cross - DISK_INNER) / (DISK_OUTER - DISK_INNER)
        disk_phi_norm = disk_phi / (2 * np.pi)

        # Doppler factor: Keplerian orbital velocity v = sqrt(M/(2r))
        # Orbital direction is tangential in the equatorial plane
        v_orb = np.sqrt(0.5 / r_cross)
        orb_dir = normalize(np.cross(disk_up, p_disk))  # prograde tangent

        # Ray direction at crossing (approximate from adjacent geodesic points)
        ray_at_cross = normalize(p_curr - p_prev)

        # Doppler: δ = 1 / (1 - v · n_obs) where n_obs is ray direction toward camera
        cos_obs = np.dot(orb_dir, -ray_at_cross)
        doppler = 1.0 / max(0.01, 1.0 - v_orb * cos_obs)
        beaming = min(doppler ** 3.5, 20.0)

        # Interpolated phi for time delay
        phi_cross = phi_prev + t * (phi_curr - phi_prev)
        time_delay = phi_cross

        # Weight: thinner crossing = sharper feature
        crossing_width = abs(y_curr - y_prev)
        weight = min(1.0, 0.01 / max(crossing_width, 1e-6))

        crossings.append({
            'uv': [float(disk_r_norm), float(disk_phi_norm)],
            'weight': float(weight),
            'doppler': float(beaming),
            'time_delay': float(time_delay),
            'r': r_cross,
        })

    return crossings


# ---------------------------------------------------------------------------
# Background source direction
# ---------------------------------------------------------------------------

def escaped_ray_direction(phis, us, e1, e2):
    """Compute the 3D direction the escaped ray came from at infinity."""
    if len(phis) < 2:
        return np.array([0, 0, 1])

    # Use the last two points to get the asymptotic direction
    u1, u2 = us[-2], us[-1]
    if u1 < 1e-10:
        u1 = 1e-10
    if u2 < 1e-10:
        u2 = 1e-10

    r1, r2 = 1.0/u1, 1.0/u2
    p1 = orbital_to_3d(r1, phis[-2], e1, e2)
    p2 = orbital_to_3d(r2, phis[-1], e1, e2)

    return normalize(p2 - p1)


def direction_to_equirect_uv(d):
    """Map a 3D direction to equirectangular UV."""
    phi = np.arctan2(d[2], d[0])
    if phi < 0:
        phi += 2 * np.pi
    theta = np.arccos(np.clip(d[1], -1, 1))
    u = phi / (2 * np.pi)
    v = theta / np.pi
    return u, v


# ---------------------------------------------------------------------------
# Full ray trace
# ---------------------------------------------------------------------------

def trace_ray(cam_pos, ray_dir):
    """Trace one ray, return full transport record."""

    u_cam, u_dot, e_sq, delta = ray_initial_conditions(cam_pos, ray_dir)
    e1, e2, normal = build_orbital_basis(cam_pos, ray_dir)

    record = {
        'bg_uv': [0.0, 0.0],
        'magnification': 1.0,
        'capture': 0.0,
        'disk0_uv': [0.0, 0.0], 'disk0_weight': 0.0, 'disk0_doppler': 0.0,
        'disk1_uv': [0.0, 0.0], 'disk1_weight': 0.0, 'disk1_doppler': 0.0,
        'caustic': 0.0, 'time_delay': 0.0, 'mip_bias': 0.0, 'class_mask': 0.0,
    }

    # Integrate geodesic
    phis, us, uds = integrate_geodesic(u_cam, u_dot)

    if len(phis) < 2:
        record['capture'] = 1.0
        return record

    # Captured?
    if us[-1] >= 1.0:
        # Still check for disk crossings before capture
        crossings = find_disk_crossings(phis, us, e1, e2)
        record['capture'] = 1.0
        if crossings:
            c = crossings[0]
            record['disk0_uv'] = c['uv']
            record['disk0_weight'] = c['weight']
            record['disk0_doppler'] = c['doppler']
            record['time_delay'] = c['time_delay']
            record['class_mask'] = 1.0
        return record

    # Escaped — compute background source direction
    esc_dir = escaped_ray_direction(phis, us, e1, e2)
    bg_u, bg_v = direction_to_equirect_uv(esc_dir)
    record['bg_uv'] = [float(bg_u), float(bg_v)]

    # Magnification (approximate: ratio of solid angles)
    e_sq_norm = e_sq / MU
    if 0.95 < e_sq_norm < 1.05:
        closeness = 1.0 - abs(e_sq_norm - 1.0) / 0.05
        record['magnification'] = float(1.0 + 9.0 * closeness)
        record['caustic'] = float(closeness)
    else:
        record['magnification'] = 1.0

    # Disk crossings
    crossings = find_disk_crossings(phis, us, e1, e2)

    if len(crossings) >= 1:
        c = crossings[0]
        record['disk0_uv'] = c['uv']
        record['disk0_weight'] = c['weight']
        record['disk0_doppler'] = c['doppler']
        record['time_delay'] = c['time_delay']
        record['class_mask'] = 1.0

    if len(crossings) >= 2:
        c = crossings[1]
        record['disk1_uv'] = c['uv']
        record['disk1_weight'] = c['weight']
        record['disk1_doppler'] = c['doppler']
        record['class_mask'] = 2.0

    # Photon ring: rays near critical impact parameter
    if 0.97 < e_sq_norm < 1.03:
        ring = 1.0 - abs(e_sq_norm - 1.0) / 0.03
        record['caustic'] = float(max(record['caustic'], ring))

    # MIP bias
    record['mip_bias'] = float(min(np.log2(max(record['magnification'], 1.0)), 4.0))

    return record


# ---------------------------------------------------------------------------
# Camera
# ---------------------------------------------------------------------------

def config3_camera(resolution, view_slice=0):
    """
    Build camera rays to reproduce Config 3's visual composition.

    Config 3 shows:
      - Event horizon shadow fills upper ~40% of frame
      - Accretion disk fills bottom, arcs over the top
      - Camera is near-equatorial, slightly above disk plane
      - BH is off-center right, text space on the left

    We set this up directly in Schwarzschild coordinates rather than
    trying to map MisterPrada's object-space camera.

    The critical impact parameter is b_crit = sqrt(27)/2 ≈ 2.598 r_s.
    From distance r, the BH shadow subtends θ ≈ arcsin(b_crit / r).
    For θ ≈ 25° (filling ~50% of 50° FOV): r ≈ b_crit / sin(25°) ≈ 6.15
    """
    fov_deg = 50.0

    # Camera position: near-equatorial, slightly above disk plane
    # r ≈ 4.5 r_s — danger close, disk fills lower frame
    # b_crit = sqrt(27)/2 ≈ 2.598; shadow angle ≈ arcsin(2.598/4.5) ≈ 35°
    cam_r = 4.5
    cam_elev = np.radians(8.0)   # 8° above equatorial — sees disk surface below
    cam_azimuth = np.radians(0.0)

    cam_pos = np.array([
        cam_r * np.cos(cam_elev) * np.sin(cam_azimuth),
        cam_r * np.sin(cam_elev),
        cam_r * np.cos(cam_elev) * np.cos(cam_azimuth),
    ])

    # Target: offset left and slightly up — puts BH shadow right of center
    target = np.array([-1.2, 0.3, 0.0])

    # View slice: subtle azimuthal rotation
    if view_slice > 0:
        angle = view_slice * 0.04
        c, s = np.cos(angle), np.sin(angle)
        x, z = cam_pos[0], cam_pos[2]
        cam_pos[0] = x * c - z * s
        cam_pos[2] = x * s + z * c

    # Camera basis
    forward = normalize(target - cam_pos)
    world_up = np.array([0.0, 1.0, 0.0])
    right = normalize(np.cross(forward, world_up))
    up = np.cross(right, forward)

    half_fov = np.tan(np.radians(fov_deg / 2.0))

    rays = []
    for j in range(resolution):
        for i in range(resolution):
            # NDC: i=0 → left, j=0 → top (standard image convention)
            ndc_x = 2.0 * (i + 0.5) / resolution - 1.0
            ndc_y = -(2.0 * (j + 0.5) / resolution - 1.0)  # flip Y for image coords
            ray_dir = normalize(forward + right * ndc_x * half_fov + up * ndc_y * half_fov)
            rays.append(ray_dir)

    return cam_pos, np.array(rays)


# ---------------------------------------------------------------------------
# Atlas generation
# ---------------------------------------------------------------------------

def generate_atlas(resolution, view_slice, output_dir):
    print(f"Generating transport atlas: {resolution}x{resolution}, slice {view_slice}")

    cam_pos, rays = config3_camera(resolution, view_slice)
    print(f"  Camera at r = {np.linalg.norm(cam_pos):.2f} r_s, pos = {cam_pos}")

    n = resolution * resolution
    bg   = np.zeros((n, 4), dtype=np.float32)
    d0   = np.zeros((n, 4), dtype=np.float32)
    d1   = np.zeros((n, 4), dtype=np.float32)
    aux  = np.zeros((n, 4), dtype=np.float32)

    report_interval = max(n // 20, 1)

    for idx in range(n):
        if idx % report_interval == 0:
            print(f"  {100*idx/n:.0f}%")

        rec = trace_ray(cam_pos, rays[idx])

        bg[idx]  = [rec['bg_uv'][0], rec['bg_uv'][1], rec['magnification'], rec['capture']]
        d0[idx]  = [rec['disk0_uv'][0], rec['disk0_uv'][1], rec['disk0_weight'], rec['disk0_doppler']]
        d1[idx]  = [rec['disk1_uv'][0], rec['disk1_uv'][1], rec['disk1_weight'], rec['disk1_doppler']]
        aux[idx] = [rec['caustic'], rec['time_delay'], rec['mip_bias'], rec['class_mask']]

    # Convert to float16 and save
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    suffix = f"_s{view_slice}"
    for name, data in [('transport_bg', bg), ('transport_disk0', d0),
                       ('transport_disk1', d1), ('transport_aux', aux)]:
        fpath = output_dir / f"{name}{suffix}.bin"
        data.astype(np.float16).tofile(fpath)
        print(f"    {fpath.name}: {fpath.stat().st_size / 1024:.1f} KB")

    return {
        'view_slice': view_slice,
        'resolution': resolution,
        'files': {k: f"{k}{suffix}.bin" for k in
                  ['transport_bg', 'transport_disk0', 'transport_disk1', 'transport_aux']}
    }


def write_manifest(slices, output_dir):
    manifest = {
        "id": "arclight-blackhole-hero-v001",
        "renderModel": "precomputed-transport-live-composite",
        "coordinateSpace": "blackhole-local-uv",
        "resolution": [RESOLUTION, RESOLUTION],
        "viewSlices": len(slices),
        "metric": "schwarzschild",
        "disk": {"innerRadius": DISK_INNER, "outerRadius": DISK_OUTER},
        "maps": {s['view_slice']: s['files'] for s in slices},
        "format": "float16-rgba",
        "attribution": "Geodesic method adapted from ebruneton/black_hole_shader (BSD-3-Clause)"
    }
    p = Path(output_dir) / "manifest.json"
    p.write_text(json.dumps(manifest, indent=2))
    print(f"Manifest: {p}")


def main():
    output_dir = Path(__file__).parent.parent / "assets" / "lens"

    resolution = RESOLUTION
    num_slices = 4

    if '--preview' in sys.argv:
        resolution = 128
        num_slices = 1
        print("PREVIEW MODE: 128x128, 1 slice")

    if '--medium' in sys.argv:
        resolution = 256
        num_slices = 1
        print("MEDIUM MODE: 256x256, 1 slice")

    slices = []
    for s in range(num_slices):
        slices.append(generate_atlas(resolution, s, output_dir))
    write_manifest(slices, output_dir)
    print("Done.")


if __name__ == '__main__':
    main()
