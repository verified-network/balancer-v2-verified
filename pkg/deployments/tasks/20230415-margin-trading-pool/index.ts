import Task from '../../src/task';
import { TaskRunOptions } from '../../src/types';
import { MarginTradingPoolDeployment } from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as MarginTradingPoolDeployment;
  const args = [input.Vault, input.ProtocolFeePercentagesProvider];
  await task.deployAndVerify('MarginTradingPoolFactory', args, from, force);
};
