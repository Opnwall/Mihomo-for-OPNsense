<?php

/*
 * Copyright (C) 2024  https://pfchina.org/
 * All rights reserved.
 *
 */

function mosdns_services()
{
    global $config;

    $services = array();

        $services[] = array(
            'description' => gettext('mosdns'),
            'configd' => array(
                'restart' => array('mosdns restart'),
                'start' => array('mosdns start'),
                'stop' => array('mosdns stop'),
            ),
            'name' => 'mosdns',
            'pidfile' => '/var/run/mosdns.pid',
        );
    

    return $services;
}
function mosdns_syslog()
{
    $logfacilities = array();
    $logfacilities['mosdns'] = array(
        'facility' => array('mosdns'),
    );
    return $logfacilities;
}