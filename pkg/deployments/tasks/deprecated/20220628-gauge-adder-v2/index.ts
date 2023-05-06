<<<<<<< HEAD:pkg/deployments/tasks/20220628-gauge-adder-v2/index.ts
import Task from '../../src/task';
import { TaskRunOptions } from '../../src/types';
import { GaugeAdderDeployment } from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as GaugeAdderDeployment;

  const gaugeAdderArgs = [input.GaugeController, input.PreviousGaugeAdder];
  await task.deployAndVerify('GaugeAdder', gaugeAdderArgs, from, force);
};
=======
import Task from '../../../src/task';
import { TaskRunOptions } from '../../../src/types';
import { GaugeAdderDeployment } from './input';

export default async (task: Task, { force, from }: TaskRunOptions = {}): Promise<void> => {
  const input = task.input() as GaugeAdderDeployment;

  const gaugeAdderArgs = [input.GaugeController, input.PreviousGaugeAdder];
  await task.deployAndVerify('GaugeAdder', gaugeAdderArgs, from, force);
};
>>>>>>> origin/master:pkg/deployments/tasks/deprecated/20220628-gauge-adder-v2/index.ts
