<<<<<<< HEAD:pkg/deployments/tasks/20220325-single-recipient-gauge-factory/input.ts
import Task, { TaskMode } from '../../src/task';

export type SingleRecipientFactoryDelegationDeployment = {
  BalancerMinter: string;
};

const BalancerMinter = new Task('20220325-gauge-controller', TaskMode.READ_ONLY);

export default {
  BalancerMinter,
};
=======
import Task, { TaskMode } from '../../../src/task';

export type SingleRecipientFactoryDelegationDeployment = {
  BalancerMinter: string;
};

const BalancerMinter = new Task('20220325-gauge-controller', TaskMode.READ_ONLY);

export default {
  BalancerMinter,
};
>>>>>>> origin/master:pkg/deployments/tasks/deprecated/20220325-single-recipient-gauge-factory/input.ts
