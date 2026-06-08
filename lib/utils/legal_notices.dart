import 'package:flutter/material.dart';

const unofficialServiceNotice =
    '本サービスは、北海道大学の学生を主な対象とした非公式サービスです。北海道大学、北海道大学生活協同組合、各学部・部局とは関係ありません。掲載情報はユーザーまたは団体による投稿内容であり、大学による確認・承認を意味するものではありません。';

const handoverSafetyNotice =
    '受け渡し場所・日時は当事者間で相談して決めてください。大学施設、店舗、公共施設などを利用する場合は、各施設のルールに従ってください。安全のため、人目のある場所での受け渡しを推奨します。';

const stripeConnectBalanceNotice =
    '売上の入金・管理はStripe Connectを通じて行われます。本サービス内に売上金残高を保持する機能はありません。';

const prDisclaimerNotice = 'この掲載は団体によるPRです。北海道大学による確認・承認を意味するものではありません。';

const listingOwnershipNotice =
    '私はこの商品を本人所有の不要品として出品します。代理出品・買取品・預かり品・転売目的の商品ではありません。';

const prohibitedListingNotice =
    '出品できるのは、本人所有の教科書・参考書・問題集・専門書・授業用品など、授業に関係する市販の物理的な物品です。授業プリント、レジュメ、配布資料、講義スライドのコピー、講義ノート・板書の写し、電子教材のアカウントやアクセスコード、代理出品・買取品・預かり品、授業と関係のない物品は出品できません。';

class InformationCard extends StatelessWidget {
  const InformationCard({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.info_outline,
  });

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  style: TextStyle(
                    color: Colors.grey.shade800,
                    fontSize: 12,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PrBadge extends StatelessWidget {
  const PrBadge({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        (label == null || label!.trim().isEmpty) ? 'PR' : label!.trim(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
