## AuthRepository.sign_up() / sign_in() の結果。成功なら session を持つ。
## UseCase ごとの結果型は共用しない方針（architecture.md）に沿い、契約ごとの専用型にしてある
## （master_data の MasterVersionResult と同じ作り）。
class_name AuthSessionResult
extends Result

var session: AuthSession = null


func _init(p_session: AuthSession = null, p_error: AppError = null) -> void:
	super(p_error == null, p_error)
	session = p_session
