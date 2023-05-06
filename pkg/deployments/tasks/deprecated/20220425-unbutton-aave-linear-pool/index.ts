<<<<<<< HEAD:pkg/deployments/tasks/20220425-unbutton-aave-linear-pool/index.ts
import Task from '../../src/task';
import { TaskRunOptions } from '../../src/types';
import { UnbuttonAaveLinearPoolDeployment } from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as UnbuttonAaveLinearPoolDeployment;
  const args = [input.Vault];
  await task.deployAndVerify('UnbuttonAaveLinearPoolFactory', args, from, force);
};
=======
import Task from '../../../src/task';
import { TaskRunOptions } from '../../../src/types';
import { UnbuttonAaveLinearPoolDeployment } from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as UnbuttonAaveLinearPoolDeployment;
  const args = [input.Vault];
  await task.deployAndVerify('UnbuttonAaveLinearPoolFactory', args, from, force);
};
>>>>>>> origin/master:pkg/deployments/tasks/deprecated/20220425-unbutton-aave-linear-pool/index.ts
