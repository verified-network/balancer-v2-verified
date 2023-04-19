import Task from '../../src/task';
import { TaskRunOptions } from '../../src/types';
import { OffchainSecondariesPoolDeployment } from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as OffchainSecondariesPoolDeployment;
  const args = [input.Vault, input.ProtocolFeePercentagesProvider];
  await task.deployAndVerify('OffchainSecondariesPoolFactory', args, from, force);
};
