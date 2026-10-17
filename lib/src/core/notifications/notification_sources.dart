/// Official Android identities, not evidence of verified transaction templates.
/// See docs/MALAYSIA_BANK_NOTIFICATION_RESEARCH.md and
/// docs/TNG_NOTIFICATION_RESEARCH.md. Every listed source requires review.
class NotificationSourceProfile {
  const NotificationSourceProfile({
    required this.institution,
    required this.appName,
    required this.packageName,
  });

  final String institution;
  final String appName;
  final String packageName;

  String get reviewReason => '$appName 通知格式尚未完成验证，请核对后记账';
}

const malaysiaBankNotificationSources = <NotificationSourceProfile>[
  NotificationSourceProfile(
    institution: 'Maybank',
    appName: 'MAE by Maybank2u',
    packageName: 'com.maybank2u.life',
  ),
  NotificationSourceProfile(
    institution: 'CIMB',
    appName: 'CIMB OCTO MY',
    packageName: 'com.cimb.cimbocto',
  ),
  NotificationSourceProfile(
    institution: 'Public Bank',
    appName: 'MyPB by Public Bank',
    packageName: 'com.pbb.mypb',
  ),
  NotificationSourceProfile(
    institution: 'RHB',
    appName: 'RHB Mobile Banking',
    packageName: 'com.rhbgroup.rhbmobilebanking',
  ),
  NotificationSourceProfile(
    institution: 'Hong Leong Bank',
    appName: 'HLB Connect Mobile Banking App',
    packageName: 'my.com.hongleongconnect.mobileconnect',
  ),
  NotificationSourceProfile(
    institution: 'AmBank',
    appName: 'AmOnline',
    packageName: 'com.ambank.ambankonline',
  ),
  NotificationSourceProfile(
    institution: 'Bank Islam',
    appName: 'BIMB Mobile',
    packageName: 'com.bankislam.bimbmobile',
  ),
  NotificationSourceProfile(
    institution: 'Bank Rakyat',
    appName: 'iRakyat Mobile Banking',
    packageName: 'com.irakyatmob.bkrm',
  ),
  NotificationSourceProfile(
    institution: 'BSN',
    appName: 'myBSN',
    packageName: 'com.bsn.mybsn',
  ),
  NotificationSourceProfile(
    institution: 'Affin Bank',
    appName: 'AffinAlwaysX',
    packageName: 'com.affin.mobilebanking',
  ),
];

const tngEwalletPackage = 'my.com.tngdigital.ewallet';

const reviewOnlyNotificationSources = <NotificationSourceProfile>[
  ...malaysiaBankNotificationSources,
  NotificationSourceProfile(
    institution: 'TNG Digital',
    appName: 'TNG eWallet',
    packageName: tngEwalletPackage,
  ),
];

/// Exact package matching avoids applying a bank policy to a similarly named
/// app, a regional variant, or a retired app with a different identity.
NotificationSourceProfile? notificationSourceFor(String? packageName) {
  for (final source in reviewOnlyNotificationSources) {
    if (source.packageName == packageName) return source;
  }
  return null;
}
