use crate::{Context, CoreError};
use glutin::api::egl::context::PossiblyCurrentContext;
use glutin::api::egl::device::Device;
use glutin::api::egl::display::Display;
use glutin::config::{ConfigSurfaceTypes, ConfigTemplateBuilder, GlConfig};
use glutin::context::{ContextApi, ContextAttributesBuilder};
use glutin::display::GlDisplay;
use glutin::prelude::*;
use std::rc::Rc;
use thiserror::Error;

///
/// Error associated with a headless context.
///
#[derive(Error, Debug)]
#[allow(missing_docs)]
pub enum HeadlessError {
    #[error("error in three-d")]
    ThreeDError(#[from] CoreError),
}

///
/// A headless graphics context, ie. a graphics context that is not associated with any window.
/// For a graphics context associated with a window, see [WindowedContext](crate::WindowedContext).
/// Can only be created on native, not on web.
///
#[derive(Clone)]
pub struct HeadlessContext {
    context: Context,
    _glutin_context: Rc<PossiblyCurrentContext>,
}

impl HeadlessContext {
    ///
    /// Creates a new headless graphics context.
    ///
    #[allow(unsafe_code)]
    pub fn new() -> Result<Self, HeadlessError> {
        let devices = Device::query_devices()
            .expect("Failed to query devices")
            .collect::<Vec<_>>();

        for (index, device) in devices.iter().enumerate() {
            println!(
                "Device {}: Name: {} Vendor: {}",
                index,
                device.name().unwrap_or("UNKNOWN"),
                device.vendor().unwrap_or("UNKNOWN")
            );
        }

        let device = devices.first().expect("No available devices");

        // Create a display using the device.
        let display = unsafe {
            // Safety: unsafe condition only triggered by raw_display being Some.
            Display::with_device(device, None)
        }
        .expect("Failed to create display");

        let template = ConfigTemplateBuilder::default()
            .with_alpha_size(8)
            // Offscreen rendering has no support window surface support.
            .with_surface_type(ConfigSurfaceTypes::empty())
            .build();

        let config = unsafe {
            // TODO: Argue safety?
            display.find_configs(template)
        }
        .unwrap()
        .reduce(|config, acc| {
            if config.num_samples() > acc.num_samples() {
                config
            } else {
                acc
            }
        })
        .expect("No available configs");

        println!("Picked a config with {} samples", config.num_samples());

        // Context creation.
        //
        // In particular, since we are doing offscreen rendering we have no raw window
        // handle to provide.
        let context_attributes = ContextAttributesBuilder::new().build(None);

        // Since glutin by default tries to create OpenGL core context, which may not be
        // present we should try gles.
        let fallback_context_attributes = ContextAttributesBuilder::new()
            .with_context_api(ContextApi::Gles(None))
            .build(None);

        let not_current = unsafe {
            display
                .create_context(&config, &context_attributes)
                .unwrap_or_else(|_| {
                    display
                        .create_context(&config, &fallback_context_attributes)
                        .expect("failed to create context")
                })
        };

        let current = not_current.make_current_surfaceless().unwrap();

        let glow_context = unsafe {
            glow::Context::from_loader_function_cstr(|name| {
                display.get_proc_address(name) as *const _
            })
        };

        let context = Context::from_gl_context(glow_context.into()).expect("TODO: panic message");

        Ok(Self {
            context,
            _glutin_context: Rc::new(current),
        })
    }
}

impl std::ops::Deref for HeadlessContext {
    type Target = Context;
    fn deref(&self) -> &Self::Target {
        &self.context
    }
}
