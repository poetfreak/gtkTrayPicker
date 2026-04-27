#pragma once

Extern "C"

Type AppIndicator As Any

Declare Function app_indicator_new CDecl Alias "app_indicator_new" ( _
    ByVal id As Const ZString Ptr, _
    ByVal icon_name As Const ZString Ptr, _
    ByVal category As Integer) As AppIndicator Ptr

Declare Sub app_indicator_set_status CDecl Alias "app_indicator_set_status" ( _
    ByVal indicator As AppIndicator Ptr, _
    ByVal status As Integer)

Declare Sub app_indicator_set_menu CDecl Alias "app_indicator_set_menu" ( _
    ByVal indicator As AppIndicator Ptr, _
    ByVal menu As GtkMenu Ptr)

Declare Sub app_indicator_set_secondary_activate_target CDecl Alias "app_indicator_set_secondary_activate_target" ( _
    ByVal indicator As AppIndicator Ptr, _
    ByVal menuitem As GtkWidget Ptr)

End Extern

Const APP_INDICATOR_CATEGORY_APPLICATION_STATUS = 0
Const APP_INDICATOR_STATUS_ACTIVE = 1
