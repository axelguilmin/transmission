set(MAC_WIDGET_BUNDLE_NAME TransmissionWidget)

add_executable(${TR_NAME}-mac-widget MACOSX_BUNDLE)

target_sources(${TR_NAME}-mac-widget
    PRIVATE
        Shared/WidgetSnapshot.swift
        TransmissionWidget.swift)

set(LINGUAS
    en)

set(LANG_STRINGS_FILES
    Localizable.strings)

set(RESOURCES)

foreach(LANG ${LINGUAS})
    set(${LANG}_STRINGS_FILES)
    set(STRINGS_FILES_RESOURCES_DIR Resources)
    if(NOT CMAKE_GENERATOR STREQUAL Xcode)
        string(APPEND STRINGS_FILES_RESOURCES_DIR /${LANG}.lproj)
    endif()
    foreach(F ${LANG_STRINGS_FILES})
        list(APPEND ${LANG}_STRINGS_FILES ${LANG}.lproj/${F})
        list(APPEND RESOURCES ${${LANG}_STRINGS_FILES})
        set_source_files_properties(
            ${${LANG}_STRINGS_FILES}
            PROPERTIES
                MACOSX_PACKAGE_LOCATION ${STRINGS_FILES_RESOURCES_DIR})
    endforeach()
    source_group(Resources/${LANG}.lproj
        FILES ${${LANG}_STRINGS_FILES})
endforeach()

target_sources(${TR_NAME}-mac-widget
    PRIVATE
        ${RESOURCES})

set(ENTITLEMENTS "${CMAKE_CURRENT_SOURCE_DIR}/${MAC_WIDGET_BUNDLE_NAME}.entitlements")

set_target_properties(
    ${TR_NAME}-mac-widget
    PROPERTIES
        BUNDLE_EXTENSION appex
        MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist.in"
        OUTPUT_NAME ${MAC_WIDGET_BUNDLE_NAME}
        Swift_MODULE_NAME ${MAC_WIDGET_BUNDLE_NAME}
        XCODE_ATTRIBUTE_CODE_SIGN_ENTITLEMENTS "${ENTITLEMENTS}"
        XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY "-"
        XCODE_ATTRIBUTE_MACOSX_DEPLOYMENT_TARGET "26.0"
        XCODE_ATTRIBUTE_SWIFT_VERSION 5.0
        XCODE_PRODUCT_TYPE com.apple.product-type.app-extension)

# swiftc takes the last -target it is given, which overrides CMAKE_Swift_COMPILER_TARGET.
if(NOT CMAKE_GENERATOR STREQUAL Xcode)
    set(WIDGET_SWIFT_TARGET "SHELL:-target ${TR_SWIFT_ARCH}-apple-macosx26.0")
    target_compile_options(${TR_NAME}-mac-widget
        PRIVATE
            ${WIDGET_SWIFT_TARGET})
    target_link_options(${TR_NAME}-mac-widget
        PRIVATE
            ${WIDGET_SWIFT_TARGET})
endif()

target_link_libraries(${TR_NAME}-mac-widget
    PRIVATE
        "-framework Foundation"
        "-framework SwiftUI"
        "-framework WidgetKit")

if(NOT CMAKE_GENERATOR STREQUAL Xcode)
    add_custom_command(
        TARGET ${TR_NAME}-mac-widget
        POST_BUILD
        # swiftc -g writes a dSYM beside the executable, inside the bundle about to be signed
        COMMAND ${CMAKE_COMMAND} -E rm -rf $<TARGET_FILE:${TR_NAME}-mac-widget>.dSYM
        COMMAND ${CODESIGN_EXECUTABLE} -s - --force --entitlements "${ENTITLEMENTS}" $<TARGET_BUNDLE_DIR:${TR_NAME}-mac-widget>)
endif()

install(
    TARGETS ${TR_NAME}-mac-widget
    DESTINATION Applications/${MAC_BUNDLE_NAME}.app/Contents/PlugIns)

# Installing can strip the executable, which invalidates its signature and with it the sandbox entitlements.
install(CODE
    "execute_process(
        COMMAND \"${CODESIGN_EXECUTABLE}\" -s - --force --entitlements \"${ENTITLEMENTS}\"
            \"\$ENV{DESTDIR}${CMAKE_INSTALL_PREFIX}/Applications/${MAC_BUNDLE_NAME}.app/Contents/PlugIns/${MAC_WIDGET_BUNDLE_NAME}.appex\"
        RESULT_VARIABLE CODESIGN_RESULT)
    if(NOT CODESIGN_RESULT EQUAL 0)
        message(FATAL_ERROR \"Signing ${MAC_WIDGET_BUNDLE_NAME}.appex failed\")
    endif()")
