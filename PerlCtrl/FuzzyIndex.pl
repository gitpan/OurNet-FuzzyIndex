package Hello;

sub Hello {
	return "Hello, World";
}

=pod

=begin PerlCtrl

    %TypeLib = (
        PackageName     => 'Hello',

	# DO NOT edit the next 3 lines.
        TypeLibGUID     => '{E91B25C6-2B15-11D2-B466-0800365DA902}', 
        ControlGUID     => '{E91B25C7-2B15-11D2-B466-0800365DA902}',
        DispInterfaceIID=> '{E91B25C8-2B15-11D2-B466-0800365DA902}',

        ControlName     => 'HelloWorldControl',
        ControlVer      => 1,  
        ProgID          => 'Hello.World',
        DefaultMethod   => '',

        Methods         => {
            'Hello' => {
                    RetType             =>  VT_BSTR,
                    TotalParams         =>  0,
                    NumOptionalParams   =>  0,
                    ParamList           =>[ ]
                },
            },  # end of 'Methods'

        Properties      => {
            }
	    ,  # end of 'Properties'
        );  # end of %TypeLib

=end PerlCtrl

=cut

