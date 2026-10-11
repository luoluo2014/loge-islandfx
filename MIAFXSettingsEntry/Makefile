include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = MIAFXSettingsEntry
MIAFXSettingsEntry_FILES = \
	MIAFXEntryController.m \
	MIAFXRootViewController.m \
	MIAFXSettingsCatalog.m \
	MIAFXNumberControlCell.m \
	MIAFXPreviewView.m \
	MIAFXFilzaLauncher.m \
	../Shared/MIAFXPath.m \
	../Shared/MIAFXDefaults.m \
	../Shared/MIAFXConfig.m \
	../Shared/MIAFXLog.m \
	../Shared/MIAFXSafe.m \
	../Shared/MIAFXIPC.c
MIAFXSettingsEntry_FRAMEWORKS = UIKit Foundation QuartzCore CoreGraphics AVFoundation UniformTypeIdentifiers
MIAFXSettingsEntry_CFLAGS = -fobjc-arc -Wall -I../Shared
MIAFXSettingsEntry_LIBRARIES = roothide
MIAFXSettingsEntry_LDFLAGS = -undefined dynamic_lookup
MIAFXSettingsEntry_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk
