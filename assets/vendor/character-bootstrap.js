import * as CharacterThree from './three.module.min.js';
import { GLTFLoader } from './GLTFLoader.js';
import { clone } from './SkeletonUtils.js';
import { addRosterEyes, preloadRosterEyes } from './roster-eyes.js';

// Show a complete face on the first model frame instead of flashing blank eyes.
await preloadRosterEyes();

window.BFCharacter3D = Object.freeze({
  THREE: CharacterThree,
  GLTFLoader,
  clone,
  addRosterEyes,
});
