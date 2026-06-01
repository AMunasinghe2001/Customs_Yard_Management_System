
path = r'd:\Company\Cus_Yard_Management\lib\services\services.dart'
with open(path, 'r', encoding='utf-8') as f:
    text = f.read()

text = text.replace(
    '''  Future<List<ForfeitedPackageModel>> getExpiredAppealPackages() async {
    final data = await supabase
        .from('forfeited_packages')
        .select('*, packages(*)')
        .lt('appeal_deadline', DateTime.now().toIso8601String())
        .order('appeal_deadline', ascending: true);''',
    '''  Future<List<ForfeitedPackageModel>> getExpiredAppealPackages() async {
    final data = await supabase
        .from('forfeited_packages')
        .select('*, packages(*, package_items(*))')
        .lt('appeal_deadline', DateTime.now().toIso8601String())
        .order('appeal_deadline', ascending: true);'''
)

text = text.replace(
    '''  Future<List<ForfeitedPackageModel>> getForfeitedPackages() async {
    final data = await supabase
        .from('forfeited_packages')
        .select('*, packages(*)').order('forfeited_at', ascending: false);''',
    '''  Future<List<ForfeitedPackageModel>> getForfeitedPackages() async {
    final data = await supabase
        .from('forfeited_packages')
        .select('*, packages(*, package_items(*))').order('forfeited_at', ascending: false);'''
)


with open(path, 'w', encoding='utf-8') as f:
    f.write(text)

