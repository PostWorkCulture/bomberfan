import * as CharacterThree from './three.module.min.js';
import { GLTFLoader } from './GLTFLoader.js';
import { clone } from './SkeletonUtils.js';

window.BFCharacter3D = Object.freeze({
  THREE: CharacterThree,
  GLTFLoader,
  clone,
});
