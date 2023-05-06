<<<<<<< HEAD:pkg/deployments/tasks/20220325-gauge-adder/input.ts
import Task, { TaskMode } from '../../src/task';

export type GaugeAdderDeployment = {
  GaugeController: string;
};

const GaugeController = new Task('20220325-gauge-controller', TaskMode.READ_ONLY);

export default {
  GaugeController,
};
=======
import Task, { TaskMode } from '../../../src/task';

export type GaugeAdderDeployment = {
  GaugeController: string;
};

const GaugeController = new Task('20220325-gauge-controller', TaskMode.READ_ONLY);

export default {
  GaugeController,
};
>>>>>>> origin/master:pkg/deployments/tasks/deprecated/20220325-gauge-adder/input.ts
