import { Decimal } from 'decimal.js';
import { BigNumber } from 'ethers';

import { decimal, fromFp, toFp, scaleDown, fp } from '@balancer-labs/v2-helpers/src/numbers';

export type Params = {
  fee: BigNumber;
  minPrice: BigNumber;
  minimumOrderSize: BigNumber;
};

export function calcCashOutPerSecurityIn(fpSecurityIn: BigNumber, fpSecurityBalance: BigNumber, fpCashBalance: BigNumber, params: Params): Decimal {
  const securityIn = decimal(fpSecurityIn);
  const securityBalance = decimal(fpSecurityBalance);
  const cashBalance = decimal(fpCashBalance);
  const minPrice = decimal(params.minPrice);
  const minimumOrderSize = decimal(params.minimumOrderSize);

  const postPaidSecurityBalance = securityBalance.add(securityIn.toString());
  
  const tokensOut = (postPaidSecurityBalance.div(securityBalance)).mul(securityIn.mul(minPrice));
  
  return fromFp(fromFp(tokensOut));
}

export function calcSecurityOutPerCashIn(fpCashIn: BigNumber, fpSecurityBalance: BigNumber, fpCashBalance: BigNumber, params: Params): Decimal {
  const cashIn = decimal(fpCashIn);
  const securityBalance = decimal(fpSecurityBalance);
  const cashBalance = decimal(fpCashBalance);
  const minPrice = decimal(params.minPrice);
  const minimumOrderSize = decimal(params.minimumOrderSize);

  const postPaidCurrencyBalance = cashBalance.add(cashIn.toString());
  let tokensOut = (cashIn.div(minPrice)).div(postPaidCurrencyBalance.div(cashBalance));

  return toFp(tokensOut);
}

export function calcCashInPerSecurityOut(fpSecurityOut: BigNumber, fpSecurityBalance: BigNumber, fpCashBalance: BigNumber, params: Params): Decimal {
  const securityOut = decimal(fpSecurityOut);
  const securityBalance = decimal(fpSecurityBalance);
  const cashBalance = decimal(fpCashBalance);
  const minPrice = decimal(params.minPrice);
  const minimumOrderSize = decimal(params.minimumOrderSize);

  const postPaidSecurityBalance = securityBalance.sub(securityOut.toString());
  let tokensIn = (securityBalance.div(postPaidSecurityBalance)).mul(securityOut.mul(minPrice));

  return fromFp(tokensIn);
}

export function calcSecurityInPerCashOut(fpCashOut: BigNumber, fpSecurityBalance: BigNumber, fpCashBalance: BigNumber, params: Params): Decimal {
  const cashOut = decimal(fpCashOut);
  const securityBalance = decimal(fpSecurityBalance);
  const cashBalance = decimal(fpCashBalance);
  const minPrice = decimal(params.minPrice);
  const minimumOrderSize = decimal(params.minimumOrderSize);

  const postPaidCurrencyBalance = cashBalance.sub(cashOut.toString());
  const tokensIn = (cashOut.div(minPrice)).div(cashBalance.div(postPaidCurrencyBalance));

  return toFp(tokensIn);
}

