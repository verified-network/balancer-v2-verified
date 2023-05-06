<<<<<<< HEAD:pkg/deployments/tasks/20220425-unbutton-aave-linear-pool/input.ts
import Task, { TaskMode } from '../../src/task';

export type UnbuttonAaveLinearPoolDeployment = {
  Vault: string;
};

const Vault = new Task('20210418-vault', TaskMode.READ_ONLY);

export default {
  Vault,
};
=======
import Task, { TaskMode } from '../../../src/task';

export type UnbuttonAaveLinearPoolDeployment = {
  Vault: string;
};

const Vault = new Task('20210418-vault', TaskMode.READ_ONLY);

export default {
  Vault,
};
>>>>>>> origin/master:pkg/deployments/tasks/deprecated/20220425-unbutton-aave-linear-pool/input.ts
