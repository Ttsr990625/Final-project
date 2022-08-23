#version 460
#extension GL_EXT_ray_tracing : enable
#extension GL_GOOGLE_include_directive : require
//#extension GL_EXT_shader_explicit_arithmetic_types_int64 : require

#include "../shared_with_shaders.h"

layout(set = SWS_SCENE_AS_SET,     binding = SWS_SCENE_AS_BINDING)            uniform accelerationStructureEXT Scene;
layout(set = SWS_RESULT_IMAGE_SET, binding = SWS_RESULT_IMAGE_BINDING, rgba8) uniform image2D ResultImage;

layout(set = SWS_CAMDATA_SET,      binding = SWS_CAMDATA_BINDING, std140)     uniform AppData {
    UniformParams Params;
};

layout(location = SWS_LOC_PRIMARY_RAY) rayPayloadEXT RayPayload PrimaryRay;
layout(location = SWS_LOC_SHADOW_RAY)  rayPayloadEXT ShadowRayPayload ShadowRay;

const float RefractionIndex = 1.0f / 1.31f;

vec3 CalcRayDir(vec2 screenUV, float aspect) {
    vec3 u = Params.camSide.xyz;
    vec3 v = Params.camUp.xyz;

    const float planeWidth = tan(Params.camNearFarFov.z * 0.5f);

    u *= (planeWidth * aspect);
    v *= planeWidth;

    const vec3 rayDir = normalize(Params.camDir.xyz + (u * screenUV.x) - (v * screenUV.y));
    return rayDir;
}

void main() {
    //const vec2 uv = (vec2(gl_LaunchIDEXT.xy) / vec2(gl_LaunchSizeEXT.xy - 1)); 
    const vec2 uv = (vec2(gl_LaunchIDEXT.xy) / vec2(gl_LaunchSizeEXT.xy - 1))* 2.0f - 1.0f;
    const float aspect = float(gl_LaunchSizeEXT.x) / float(gl_LaunchSizeEXT.y);

    vec3 origin = Params.camPos.xyz;
   // vec3 direction = vec3(0.0f, 0.0f, 1.0f);
    vec3 direction = CalcRayDir(uv, aspect);

    const uint rayFlags = gl_RayFlagsOpaqueEXT;
     // const uint rayFlags = gl_RayFlagsNoneEXT;
    const uint shadowRayFlags = gl_RayFlagsOpaqueEXT | gl_RayFlagsTerminateOnFirstHitEXT;


    const uint stbRecordStride = 0;

    const float tmin = 0.0f;
    const float tmax = Params.camNearFarFov.y;

   vec3 finalColor = vec3(0.0f);
                 

    for (int i = 0; i < SWS_MAX_RECURSION; ++i) {
        traceRayEXT(Scene, //TLAS
                    rayFlags,
                    0xFF,   
                    SWS_PRIMARY_HIT_SHADERS_IDX, //0 sbtRecordOffset
                    1, // sbtRecordStride
                    SWS_PRIMARY_MISS_SHADERS_IDX, //0  missIndex
                    origin,
                    tmin,
                    direction,
                    tmax,               
                    SWS_LOC_PRIMARY_RAY);// payload (location = 0)

        const vec3 hitColor = PrimaryRay.colorAndDis.rgb;
        const float hitDistance = PrimaryRay.colorAndDis.w;

        // if hit background - quit
        if (hitDistance < 0.0f) {
           finalColor += hitColor;
            break;
        } else {
            const vec3 hitNormal = PrimaryRay.posAndObjId.xyz;
            const float objectId = PrimaryRay.posAndObjId.w;

            const vec3 hitPos = origin + direction * hitDistance;
           if (objectId == 2.0f )
         {
               origin = hitPos + hitNormal * 0.0001f;
              direction = reflect(direction, hitNormal);
          }
        //    if (objectId == 2.0f) {
                

          //     const float NdotD = dot(hitNormal, direction);

          //    vec3 refrNormal = hitNormal;
          //    float refrEta;

          //    if(NdotD > 0.0f) {
          //       refrNormal = -hitNormal;
          //        refrEta = 1.0f / RefractionIndex;
         //       }
         // else {
        //          refrNormal = hitNormal;
        //            refrEta = RefractionIndex;
       //       }

       //      origin = hitPos + direction * 0.0001f;
       //       direction = refract(direction, refrNormal, refrEta);
       //   } 
          else {
                
                const vec3 toLight = normalize(Params.sunPosAndAmbient.xyz);
                const vec3 shadowRayOrigin = hitPos + hitNormal * 0.0001f;
                 float lighting = 0.0f;
                traceRayEXT(Scene,
                            shadowRayFlags,
                            0xFF,
                            1,
                            0,
                            1,
                            shadowRayOrigin,
                            0.0f,
                            toLight,//Direction of light source
                            tmax,
                            2);
               if(ShadowRay.distance > 0.0f){
               lighting = 0.1f;
                
               }else{           
                 lighting = max(0.1f, dot(PrimaryRay.posAndObjId.xyz, normalize(Params.sunPosAndAmbient.xyz)));
               }

                finalColor += hitColor * lighting;

                break;
            }
        }
    }

    imageStore(ResultImage, ivec2(gl_LaunchIDEXT.xy), vec4(LinearToSrgb(finalColor), 1.0f));
}
