<<<<<<< HEAD:pkg/deployments/tasks/20220404-erc4626-linear-pool-v2/index.ts
import Task from '../../src/task';
import { TaskRunOptions } from '../../src/types';
import { ERC4626LinearPoolDeployment } from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as ERC4626LinearPoolDeployment;
  const args = [input.Vault];
  await task.deployAndVerify('ERC4626LinearPoolFactory', args, from, force);
};
=======
import Task from '../../../src/task';
import { TaskRunOptions } from '../../../src/types';
import { ERC4626LinearPoolDeployment } from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as ERC4626LinearPoolDeployment;
  const args = [input.Vault];
  await task.deployAndVerify('ERC4626LinearPoolFactory', args, from, force);
};
>>>>>>> origin/master:pkg/deployments/tasks/deprecated/20220404-erc4626-linear-pool-v2/index.ts
