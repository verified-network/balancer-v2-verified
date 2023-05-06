<<<<<<< HEAD:pkg/deployments/tasks/20220609-stable-pool-v2/index.ts
import Task from '../../src/task';
import { TaskRunOptions } from '../../src/types';
import { StablePoolV2Deployment } from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as StablePoolV2Deployment;

  const args = [input.Vault];
  await task.deployAndVerify('StablePoolFactory', args, from, force);
};
=======
import Task from '../../../src/task';
import { TaskRunOptions } from '../../../src/types';
import { StablePoolV2Deployment } from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as StablePoolV2Deployment;

  const args = [input.Vault];
  await task.deployAndVerify('StablePoolFactory', args, from, force);
};
>>>>>>> origin/master:pkg/deployments/tasks/deprecated/20220609-stable-pool-v2/index.ts
