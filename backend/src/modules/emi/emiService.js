const emiModel = require('./emiModel');
const decouplingService = require('./decouplingService');
const firebaseService = require('../devices/firebaseService');
const logger = require('../../utils/logger');

const LOCK_REASON_CODES = {
  OVERDUE_1: { lockLevel: 'reminder', minDaysOverdue: 1, maxDaysOverdue: 3 },
  OVERDUE_3: { lockLevel: 'partial', minDaysOverdue: 3, maxDaysOverdue: 7 },
  OVERDUE_7: { lockLevel: 'full', minDaysOverdue: 7, maxDaysOverdue: 14 },
  OVERDUE_14: { lockLevel: 'full_plus', minDaysOverdue: 14 },
  SUSPECTED_SALE: { lockLevel: 'escalate', minDaysOverdue: 0 },
  SUSPECTED_FRAUD: { lockLevel: 'immediate', minDaysOverdue: 0 }
};

class EmiService {
  async createSchedule({ deviceId, totalAmount, downPayment, emiAmount, duration, startDate, graceDays = 7, dealerId }) {
    const device = await emiModel.getDeviceById(deviceId);

    if (!device) {
      throw new Error('Device not found');
    }

    if (device.schedule_id) {
      const existingSchedule = await emiModel.getScheduleByDeviceId(deviceId);
      if (existingSchedule && existingSchedule.status === 'active') {
        throw new Error('An active EMI schedule already exists for this device');
      }
    }

    if (parseFloat(downPayment) >= parseFloat(totalAmount)) {
      throw new Error('Down payment cannot be equal to or greater than total amount');
    }

    if (parseFloat(emiAmount) >= parseFloat(totalAmount)) {
      throw new Error('EMI amount must be less than total amount');
    }

    const schedule = await emiModel.createSchedule({
      deviceId,
      totalAmount,
      downPayment,
      emiAmount,
      duration,
      startDate,
      graceDays,
      dealerId
    });

    await decouplingService.initiateDecouplingFlow(deviceId, schedule.id);

    await firebaseService.writeEmiScheduleData(deviceId, {
      scheduleId: schedule.id,
      totalAmount,
      emiAmount,
      duration,
      startDate,
      graceDays,
      status: 'active'
    });

    logger.info(`EMI schedule created for device ${deviceId}: ${duration} months, ${emiAmount} BDT/month`);

    return schedule;
  }

  async getScheduleWithPayments(deviceId) {
    const schedule = await emiModel.getFullScheduleWithPayments(deviceId);

    if (!schedule) {
      return null;
    }

    const overdueStatus = await this.getOverdueStatus(deviceId);

    const installmentsWithStatus = schedule.installments.map(inst => {
      const dueDate = new Date(inst.due_date);
      const today = new Date();
      today.setHours(0, 0, 0, 0);

      const graceEndDate = new Date(dueDate);
      graceEndDate.setDate(graceEndDate.getDate() + schedule.grace_days);

      let status = 'upcoming';
      if (inst.payment_id && inst.payment_status === 'completed') {
        status = 'paid';
      } else if (today > graceEndDate) {
        status = 'overdue';
      } else if (inst.installment_number === 1 && today >= new Date(schedule.start_date)) {
        status = 'due';
      }

      return {
        ...inst,
        status,
        daysUntilDue: Math.ceil((dueDate - today) / (1000 * 60 * 60 * 24)),
        isInGrace: today <= graceEndDate && today > dueDate
      };
    });

    return {
      ...schedule,
      installments: installmentsWithStatus,
      overdueStatus,
      summary: {
        totalAmount: parseFloat(schedule.total_amount),
        amountPaid: schedule.payments.reduce((sum, p) => sum + (p.status === 'completed' ? parseFloat(p.amount) : 0), 0),
        amountRemaining: schedule.payments.reduce((sum, p) => sum + (p.status === 'completed' ? parseFloat(p.amount) : 0), 0),
        nextInstallment: installmentsWithStatus.find(i => i.status !== 'paid'),
        overdueInstallments: installmentsWithStatus.filter(i => i.status === 'overdue').length
      }
    };
  }

  async recordPayment(deviceId, { amount, method, txId, installmentNumber, note, recordedBy }) {
    const device = await emiModel.getDeviceById(deviceId);

    if (!device) {
      throw new Error('Device not found');
    }

    if (!device.schedule_id) {
      throw new Error('No EMI schedule found for this device');
    }

    const schedule = await emiModel.getScheduleByDeviceId(deviceId);
    if (!schedule || schedule.status !== 'active') {
      throw new Error('EMI schedule is not active');
    }

    const payment = await emiModel.recordPayment({
      deviceId,
      scheduleId: device.schedule_id,
      amount,
      method,
      txId,
      installmentNumber,
      note,
      recordedBy
    });

    const totalPaidResult = await require('../../config/database').query(
      `SELECT COALESCE(SUM(amount), 0) as total_paid
       FROM emi_payments
       WHERE schedule_id = $1 AND status IN ('completed', 'pending')`,
      [device.schedule_id]
    );
    const totalPaid = parseFloat(totalPaidResult.rows[0].total_paid);

    const isFinalPayment = totalPaid >= parseFloat(schedule.total_amount);

    if (isFinalPayment) {
      try {
        await decouplingService.handleFinalPayment(deviceId, {
          paymentId: payment.id,
          amount,
          totalPaid
        });

        await firebaseService.sendPushToDevice(deviceId, {
          title: 'Final Payment Received',
          body: `Congratulations! Final payment of ${amount} BDT received. Your device will be decoupled after verification.`,
          data: {
            type: 'FINAL_PAYMENT',
            deviceId,
            paymentId: payment.id
          }
        });

        logger.info(`Final payment received for device ${deviceId}. Decoupling flow initiated.`);
      } catch (error) {
        logger.error(`Failed to initiate decoupling flow for device ${deviceId}:`, error);
      }
    } else {
      await firebaseService.sendPushToDevice(deviceId, {
        title: 'Payment Recorded',
        body: `Payment of ${amount} BDT recorded successfully.`,
        data: {
          type: 'PAYMENT_RECORDED',
          deviceId,
          paymentId: payment.id
        }
      });
    }

    return {
      ...payment,
      isFinalPayment,
      remaining: Math.max(0, parseFloat(schedule.total_amount) - totalPaid)
    };
  }

  async getOverdueStatus(deviceId) {
    return emiModel.getOverdueStatus(deviceId);
  }

  async requestGracePeriod(deviceId, reason = null, requestedBy = 'dealer') {
    const gracePeriod = await emiModel.requestGracePeriod(deviceId, reason);

    const device = await emiModel.getDeviceById(deviceId);

    await firebaseService.sendPushToDevice(deviceId, {
      title: 'Grace Period Granted',
      body: 'Your dealer has requested a grace period extension. You have been granted an additional 14 days.',
      data: {
        type: 'GRACE_PERIOD_GRANTED',
        deviceId,
        daysAdded: 14
      }
    });

    await firebaseService.sendPushToDealer(device.dealer_id, {
      title: 'Grace Period Processed',
      body: `Grace period of 14 days granted for device ${device.device_name}.`,
      data: {
        type: 'GRACE_PERIOD_PROCESSED',
        deviceId
      }
    });

    logger.info(`Grace period granted for device ${deviceId}. Reason: ${reason}`);

    return gracePeriod;
  }

  async getUpcomingDueDevices(days = 7) {
    return emiModel.getUpcomingDueDevices(days);
  }

  async getLockRecommendation(deviceId) {
    const overdueStatus = await this.getOverdueStatus(deviceId);

    if (!overdueStatus.isOverdue) {
      return { action: 'none', reason: 'Payment is current' };
    }

    const daysOverdue = overdueStatus.daysOverdue;

    if (daysOverdue >= 14) {
      return {
        action: 'full_lock_plus',
        reason: 'OVERDUE_14',
        message: 'Full lock plus flag - Admin notification required',
        lockLevel: 'full_plus'
      };
    }

    if (daysOverdue >= 7) {
      return {
        action: 'full_lock',
        reason: 'OVERDUE_7',
        message: 'Full lock - Kiosk mode, emergency + dealer contact only',
        lockLevel: 'full'
      };
    }

    if (daysOverdue >= 3) {
      return {
        action: 'partial_lock',
        reason: 'OVERDUE_3',
        message: 'Partial lock - Calls, SMS, EMI app only',
        lockLevel: 'partial'
      };
    }

    return {
      action: 'reminder',
      reason: 'OVERDUE_1',
      message: 'Reminder mode - Overlay every 30 min non-dismissible',
      lockLevel: 'reminder'
    };
  }

  async validateScheduleAmounts(totalAmount, downPayment, emiAmount, duration) {
    const errors = [];

    if (parseFloat(totalAmount) <= 0) {
      errors.push('Total amount must be positive');
    }

    if (parseFloat(downPayment) < 0) {
      errors.push('Down payment cannot be negative');
    }

    if (parseFloat(downPayment) >= parseFloat(totalAmount)) {
      errors.push('Down payment must be less than total amount');
    }

    if (parseFloat(emiAmount) <= 0) {
      errors.push('EMI amount must be positive');
    }

    if (parseInt(duration) < 1 || parseInt(duration) > 60) {
      errors.push('Duration must be between 1 and 60 months');
    }

    const expectedTotal = parseFloat(downPayment) + (parseFloat(emiAmount) * parseInt(duration));
    const difference = Math.abs(expectedTotal - parseFloat(totalAmount));

    if (difference > 1) {
      errors.push(`Total amount (${totalAmount}) does not match down payment + (EMI × duration) = ${expectedTotal}`);
    }

    return {
      valid: errors.length === 0,
      errors
    };
  }

  async getDecouplingStatus(deviceId) {
    return decouplingService.getDecouplingStatus(deviceId);
  }

  async flagFraud(deviceId, flaggedBy, reason) {
    return decouplingService.flagFraud(deviceId, flaggedBy, reason);
  }

  async executeDecoupling(deviceId, rtocCode, executedBy) {
    const isValid = decouplingService.verifyRTOC(rtocCode, deviceId);

    if (!isValid) {
      throw new Error('Invalid RTOC code');
    }

    const decouplingStatus = await this.getDecouplingStatus(deviceId);

    if (!decouplingStatus) {
      throw new Error('No decoupling process found for this device');
    }

    if (decouplingStatus.pendingAdminAction) {
      return decouplingService.transitionToState(deviceId, 'DEVICE_DECOUPLED', {
        executed_by: executedBy,
        rtoc_verified: true
      });
    }

    throw new Error('Device is not in a state that allows decoupling');
  }
}

module.exports = new EmiService();