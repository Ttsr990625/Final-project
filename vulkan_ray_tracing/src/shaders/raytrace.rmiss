#version 460
#extension GL_EXT_ray_tracing : require
#extension GL_GOOGLE_include_directive : enable
#extension GL_EXT_shader_explicit_arithmetic_types_int64 : require

#include "globals.glsl"
#include "wavefront.glsl"


layout(location = 0) rayPayloadInEXT HitPayload prd;

layout(push_constant) uniform _PushConstantRay
{
    PushConstantRay pcRay;
};

void main()
{
    if (prd.depth == 0) {
        prd.hit_value = pcRay.clear_color.xyz;
    }
    else {
        prd.hit_value = 0.02 * pcRay.clear_color.xyz;   
    }
    prd.depth = pcRay.max_depth;
}