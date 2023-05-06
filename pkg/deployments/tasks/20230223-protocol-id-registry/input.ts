<<<<<<< HEAD:pkg/deployments/tasks/20220404-erc4626-linear-pool-v2/input.ts
import Task, { TaskMode } from '../../src/task';

export type ERC4626LinearPoolDeployment = {
  Vault: string;
};

const Vault = new Task('20210418-vault', TaskMode.READ_ONLY);

export default {
  Vault,
};
=======
import Task, { TaskMode } from '../../src/task';

export type ProtocolIdRegistryDeployment = {
  Vault: string;
};

const Vault = new Task('20210418-vault', TaskMode.READ_ONLY);

export default {
  Vault,
};
>>>>>>> origin/master:pkg/deployments/tasks/20230223-protocol-id-registry/input.ts
