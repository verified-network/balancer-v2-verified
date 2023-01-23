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
  
  const tokensOut = cashBalance.sub(securityBalance.mul(cashBalance.div(postPaidSecurityBalance)));
  const postPaidCurrencyBalance = cashBalance.sub(tokensOut);
  const scaleUp = toFp(postPaidCurrencyBalance.div(postPaidSecurityBalance));
  console.log("fpCashBalance",tokensOut,postPaidCurrencyBalance,scaleUp);
  return tokensOut;
}

export function calcSecurityOutPerCashIn(fpCashIn: BigNumber, fpSecurityBalance: BigNumber, fpCashBalance: BigNumber, params: Params): Decimal {
  const cashIn = decimal(fpCashIn);
  const securityBalance = decimal(fpSecurityBalance);
  const cashBalance = decimal(fpCashBalance);
  const minPrice = decimal(params.minPrice);
  const minimumOrderSize = decimal(params.minimumOrderSize);

  const postPaidCurrencyBalance = cashBalance.add(cashIn.toString());
  let tokensOut = securityBalance.sub(cashBalance.mul(securityBalance.div(postPaidCurrencyBalance)));
  if(fromFp(tokensOut)<minimumOrderSize)
    tokensOut = minimumOrderSize;
  let postPaidSecurityBalance = securityBalance.sub(tokensOut);
 
  const scaleUp = toFp(postPaidCurrencyBalance.div(postPaidSecurityBalance));

  return fromFp(tokensOut);
}

export function calcCashInPerSecurityOut(fpSecurityOut: BigNumber, fpSecurityBalance: BigNumber, fpCashBalance: BigNumber, params: Params): Decimal {
  const securityOut = decimal(fpSecurityOut);
  const securityBalance = decimal(fpSecurityBalance);
  const cashBalance = decimal(fpCashBalance);
  const minPrice = decimal(params.minPrice);
  const minimumOrderSize = decimal(params.minimumOrderSize);

  const postPaidSecurityBalance = securityBalance.sub(securityOut.toString());
  let tokensIn = (securityBalance.mul(cashBalance.div(postPaidSecurityBalance))).sub(cashBalance);
  let postPaidCurrencyBalance = cashBalance.add(tokensIn);

  const scaleUp = toFp(postPaidCurrencyBalance.div(postPaidSecurityBalance));

  return tokensIn;
}

export function calcSecurityInPerCashOut(fpCashOut: BigNumber, fpSecurityBalance: BigNumber, fpCashBalance: BigNumber, params: Params): Decimal {
  const cashOut = decimal(fpCashOut);
  const securityBalance = decimal(fpSecurityBalance);
  const cashBalance = decimal(fpCashBalance);
  const minPrice = decimal(params.minPrice);
  const minimumOrderSize = decimal(params.minimumOrderSize);

  const postPaidCurrencyBalance = cashBalance.sub(cashOut.toString());
  const tokensIn = (cashBalance.mul(securityBalance.div(postPaidCurrencyBalance))).sub(securityBalance);
  const postPaidSecurityBalance = securityBalance.add(tokensIn);
  const scaleUp = toFp(postPaidCurrencyBalance.div(postPaidSecurityBalance));

  return fromFp(tokensIn);
}

