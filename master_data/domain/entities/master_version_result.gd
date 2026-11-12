## MasterDataRemoteRepository.fetch_version() の結果。成功なら version を持つ。
## UseCase ごとの結果型は共用しない方針（architecture.md）に沿い、契約ごとの専用型にしてある。
class_name MasterVersionResult
extends Result

var version: MasterVersion = null


func _init(p_version: MasterVersion = null, p_error: AppError = null) -> void:
	super(p_error == null, p_error)
	version = p_version
