# Arena and presentation update

Implemented 10 September 2026.

- Centre the victory camera on the winner. Size the Loadout camera against the current model pose, easing focus and inward movement while pulling back immediately for raised hands. Scan only the single visible showcase model, never gameplay actors.
- Show the arena name near the top during 3, 2, 1. Use blood-red/black type and a final fade, including an opacity-only reduced-motion treatment. Clear the countdown and title at PLAY and during round teardown.
- Allow kicked bombs into player-occupied cells, sweep the movement segment against fighter positions and detonate at contact. Walls and other bombs still block travel; ordinary thrown-bomb landing and shield rules remain unchanged.
- Add two 5×2 Glacier ice platforms to the existing 5×5 islands. Four additional bridges connect the new areas to both original islands, creating loops around the original central bridge. Logical voids remain impassable and bridge cells stay crate-free. Permanent occluders remain the same eight pillars, so the existing Glacier bake stays valid.
- Add reaper and gargoyle scenery to Haunted House, with animated wing silhouettes and three alternating monster throwers.
- Replace Factory perimeter props with two forklifts and two cranes. Forklifts patrol with spinning wheels and lifting forks; cranes rotate and hoist hooks. All four take turns using the existing warning marker, wind-up and airborne bomb lifecycle.
- Aim every thrower at its chosen target throughout idle movement and shake, retaining heading briefly after release. Use the actual transformed hand/machine position as the bomb origin.
- Remove Haunted Train from level selection, Random, floor code, materials, music and lighting preloads. The active game has seven arenas and 16 fighters.

Verification: 21 simulation/resource groups across eight platform profiles, repeated twice (336 groups). Contact tests cover four kick directions, an off-centre moving victim, wall blocking and disposal. Other checks cover Glacier connectivity, four rendered floors, bridge clearance, hazard facing/release, machine movement and four successive throws, countdown lifecycle, camera centring, assets, lighting transitions and HUD work. Actual model projection coverage is recorded separately by the showcase framing test. Hosted WebGL is disabled, so final GPU visuals and physical-device FPS remain unverified.
