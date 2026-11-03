import 'dart:async';
import 'package:budget/database/tables.dart';

// Shared budgets ran on Firebase (Firestore), which this build drops.
// The functions keep their signatures so the callers still compile, but
// they do nothing: backups and sync between devices go through Google Drive.

Future<bool> shareBudget(Budget? budgetToShare, context) async => false;

Future<bool> removedSharedFromBudget(Budget sharedBudget,
        {bool removeFromServer = true}) async =>
    false;

Future<bool> leaveSharedBudget(Budget sharedBudget) async => false;

Future<bool> addMemberToBudget(
        String sharedKey, String member, Budget budget) async =>
    false;

Future<bool> removeMemberFromBudget(
        String sharedKey, String member, Budget budget) async =>
    false;

Future<dynamic> getMembersFromBudget(String sharedKey, Budget budget) async =>
    false;

Future<bool> getCloudBudgets() async => false;

Future<bool> sendTransactionSet(Transaction transaction, Budget budget) async =>
    false;

Future<bool> sendTransactionAdd(Transaction transaction, Budget budget) async =>
    false;

Future<bool> sendTransactionDelete(
        Transaction transaction, Budget budget) async =>
    false;

Future<bool> syncPendingQueueOnServer() async => false;

Future<bool> updateTransactionOnServerAfterChangingCategoryInformation(
        TransactionCategory category) async =>
    false;
