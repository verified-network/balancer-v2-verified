<<<<<<< HEAD:pkg/deployments/tasks/20220609-stable-pool-v2/input.ts
import Task, { TaskMode } from '../../src/task';

export type StablePoolV2Deployment = {
  Vault: string;
};

const Vault = new Task('20210418-vault', TaskMode.READ_ONLY);

export default {
  Vault,
};
=======
import Task, { TaskMode } from '../../src/task';

export type MerkleOrchardDeployment = {
  Vault: string;
};

const Vault = new Task('20210418-vault', TaskMode.READ_ONLY);

export default {
  Vault,
};
>>>>>>> origin/master:pkg/deployments/tasks/20230222-merkle-orchard-v2/input.ts
